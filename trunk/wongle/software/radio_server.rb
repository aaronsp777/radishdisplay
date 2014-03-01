#!/usr/bin/ruby
#
# Copyright 2009 Google Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$: << File.dirname($0)

require 'daemon'
require 'api'
require 'connection'
require 'net/http'
require 'timeout'
require 'yaml'
require 'time'
require 'optparse'

module Radish
  class RadioServer < Daemon
    include Ascii
    # conversion factor for A/D sampling
    VOLTS_PER_BIT = 3.02 / 255.0
    DEGREE_F_PER_VOLT = 1.8 / 0.01  # .01 Volts/degree C
    DEFAULT_WANGLER_URL = nil # central management url for a cluster of wongles
    #DEFAULT_WANGLER_URL = 'http://example.com:9999/wangler'

    attr_accessor :wangler_uri, :debug_level, :tty

    def initialize
      super
      never = Time.at 0
      # TODO have @lastsync survive restarts
      # keyed by remote radio address, value is epoch time
      @lasttry  = Hash.new { |h,k| never }
      @lastsync = Hash.new { |h,k| never }
      @connection = nil
      @tty = Connection.default_port
      @feedurls = read_feedurls
      @myaddr = read_my_addr
      if DEFAULT_WANGLER_URL
        @logentries = ThreadedQueue.new(&method(:sync_with_wangler))
        @wangler_uri = URI.parse DEFAULT_WANGLER_URL
      else
        @wangler_uri = nil
        @logentries = []
      end
      @debug_level = 1
    end

    def connect
      @connection = Connection.new(@tty)
    end

    # get our own radio address
    def read_my_addr
      # for now, permutate the hostname
      require 'socket'
      Socket.gethostname.unpack('H16')[0]
    end

    def read_feedurls
      # prime the feed urls in case we cannot contact the
      # wangler.  This data gets reloaded after the next contact
      # with the wangler.
      YAML.load(File.read(BASEDIR + 'feedurls')) rescue {}
    end

    # run by a separate thread
    # and sends logs to wangler and
    # receives @feedurls
    def sync_with_wangler
      sending = @logentries.to_a
      begin
        http = Net::HTTP.new @wangler_uri.host, @wangler_uri.port
        http.read_timeout = 20
        res = http.request_post @wangler_uri.request_uri, sending.to_yaml

        case res
        when Net::HTTPSuccess
          new_urls = YAML.load res.body
        else
          res.error!
        end

        # compare hashes - handles add/delete/change
        (@feedurls.keys + new_urls.keys).uniq.each do |radish|
          old_url = @feedurls[radish]
          new_url = new_urls[radish]
          next if new_url == old_url
          log_radish_change radish, old_url, new_url

          # require screen update on next checkin
          # side effect: cleans up turds on disassociation
          if old_url
            @lastsync[radish] = Time.at 0
            # TODO: maybe SignFetcher should do the unlink?
            # but this makes url changes happen way faster
            File.unlink BASEDIR + radish + '.pbm' rescue nil
          end
        end

        # update file and kick sign_fetcher if necessary
        if @feedurls != new_urls
          @feedurls = new_urls
          File.open(BASEDIR + 'feedurls','w') { |f| f.write res.body }
          notify_sign_fetcher
        end

        # Removes the entries we just posted. Low-level operations like array
        # slicing are atomic, so this is thread-safe.
        @logentries.slice! 0, sending.length

      rescue StandardError, Timeout::Error => ex
        puts "Exception talking to wangler (at %s): %s" %
          [@wangler_uri, ex.inspect]
        STDOUT.flush

        # since we are not running in the main thread,
        # we can sleep here.
        sleep 3
      end
    end

    def log_radish_change(radish, old_url, new_url)
      log nil, 'binding_change', {'mac' => radish, 'old_url' => old_url,
        'new_url' => new_url}
    end

    # wake up the sign fetcher
    # this is called if the feedurls file has changed
    def notify_sign_fetcher
      begin
        pid = readpid 'SignFetcher'
        Process.kill 'HUP', pid
      rescue => e
        puts "could not notify sign fetcher: #{e}"
      end
    end

    def log(req, event, other = {})
      # collect more parameters to log
      now = Time.now
      isotime = now.xmlschema(5)
      radish = req && req.address # nil ok
      ss = req && req.signalstrength # nil ok
      other_s = other.empty? ? '' : other.inspect

      puts [isotime, '0', radish, ss, event, other_s].join(' ')

      if @wangler_uri
        # schedule the same data to be sent up to the wangler
        @logentries << {
          'time' => now.to_f,
          'wongle' => @myaddr,
          'mac' => radish,
          'signal' => ss,
          'event' => event,
        }.merge(other)
      end
    end

    # convert pbm format to radish image format
    def pbm2raw(pbm)
      # since pbm is so similar, conversion is easy
      header, *data = pbm.unpack('A11C*')
      data.map! { |v| 255 - v } # invert bits
      raise 'BadImage' if header != "P4\n320 240\n" or data.length != 9600
      return data.pack('C*')
    end

    def memory_write_packet(start_offset, data)
      [data.length + 3, 0x00, start_offset, data].pack('CCna*')
    end

    def memory_fill_packet(start_offset, length, fill_byte)
      [6, 0x01, start_offset,
        start_offset + length - 1, fill_byte
      ].pack('CCnnC')
    end

    def display_fullscreen_packet(start_offset)
      [3, 0x18, start_offset].pack('CCn')
    end

    # new request
    def image_request(packet)
      radio = packet.address

      if packet.data.length < 4 # ignore malformed request
        log packet, 'noise', {'data' => packet.data}
        return nil
      end

      # decode and log response
      @lasttry[radio] = Time.now
      syn, rev, power, buttons, last_count, temp = packet.data.unpack 'CnCCCC'
      log packet, 'request', {
        'voltage'=> "%4.2f" % [power * VOLTS_PER_BIT],
        'revision'=> rev,
        'buttons' => buttons && ("0b%08b" % buttons),
        'reason' =>
          if    buttons & 128 != 0
            'power on'
          elsif buttons & 64  != 0
            'reset'
          elsif buttons & 1   != 0
            'button press'
          elsif buttons & 32  != 0
            'watchdog backoff'
          elsif buttons == 0
            'button release or normal wakeup'
          else
            'unknown'
          end,
        # The sample we recieve is the low 8 bits, in the voltage range .375V
        # to 1.125V. This is 4x the sensitivity of the cap reading, so we have
        # to multiply my 1/4 relative to VOLTS_PER_BIT. The offset of 32 is to
        # properly align the range, since it's shifted. We also special case
        # 0, since that's the signal that there's no sensor installed on the
        # board.
        # .01 V/degree C, 0V = -50C = -58F
        'temp' =>
          if temp == nil
            nil
          elsif temp == 0
            "0"
          else
            "%5.1f" % [(temp + 128) * (VOLTS_PER_BIT / 4) *
                       DEGREE_F_PER_VOLT - 58]
          end,
      }

      # locate file
      file = BASEDIR + radio + '.pbm'

      # don't respond to radishes we don't service it
      url = @feedurls[radio]
      if url.nil?
        log packet, 'ignore'
        return nil
      end

      # Go sleep if the radish is low on power
      if power * VOLTS_PER_BIT < 1.4
        log packet, 'cancel', {'reason' => 'power'}
        return Api.cancel(1200)
      end

      # Newer boards (with temperature sensors) can perform screen updates at
      # a much lower voltage. (As low as 1.4V.) Perform this second check for
      # the old boards that poop out at 2V.
      if power * VOLTS_PER_BIT < 2.0 and (temp == nil or temp == 0)
        log packet, 'cancel', {'reason' => 'power - old board'}
        return Api.cancel(1200)
      end

      # Don't send image if we're still waiting on sign_fetcher
      # TODO: display welcome image instead
      # while waiting for sign_fetcher
      if ! File.exists? file
        log packet, 'cancel', {'reason' => 'missing file'}
        return Api.cancel(30)
      end

      # Don't send image if contents haven't changed
      if @lastsync[radio] > File.mtime(file)
        if buttons and (buttons & 0x41 == 0x41)
          # Override if we just got reset AND are holding the app button
          log packet, 'override', {'reason' => 'secret combo engaged'}
        else
          log packet, 'cancel', {'reason' => 'no change'}
          return Api.cancel(1200)
        end
      end

      data_pbm = File.read file
      data = pbm2raw(data_pbm)

      # 100 bytes, minus 3 for new protocol overhead, minus 3 for the
      # write-to-memory command = 94 payload bytes
      last_packet = (data.length - 1) / 94
      phase0 = (0..last_packet).map do |x|
        position = x * 94
        data_chunk = data[position, 94]
        memory_write_packet(position, data_chunk)
      end
      phase1 = [display_fullscreen_packet(0)]
      response = Api::Response.new([phase0, phase1], 1200)
      # This logging is a bit verbose... but I think it'll be OK to leave
      # on. It doesn't get sent to the server.
      response.debug = (@debug_level >= 1)
      response.retries = 3

      log packet, 'send', {'url' => url, 'length' => response.length}

      return response
    end

    # finalize an existing request
    def update_state(request, state)
      source = request.address
      # record last success
      @lastsync[source] = Time.now if state == 'ack'
      elapsed = Time.now - @lasttry[source]
      log request, state, {'elapsed' => elapsed}

      return nil
    end

    def print_timing(rx)
      cycles = rx.data[1] * 256 + rx.data[2]
      ticks = cycles * 6 + 12
      log rx, 'timing', {
        'seconds' => ticks / 1000000.0,
        'cycles' => cycles,
      }
      return nil
    end

    def run
      Thread.abort_on_exception = true
      log nil, 'startup'

      for radish, url in @feedurls
        log_radish_change radish, 'startup', url
      end

      api = Api.new(@connection)
      api.debug = (@debug_level >= 2)
      api.dispatch_loop do |rx|
        if debug_level >= 2
          puts "Received data: %s (%s)" % [
            rx.data.inspect,
            rx.data.unpack('C*').map {|x| "%X" % x}.join(' ')
          ]
        end

        # determine response based on first byte
        # of request
        case rx.data[0].chr
        when SYN
          image_request rx
        when ACK
          update_state rx, 'ack'
        when NAK
          update_state rx, 'nak'
        when CAN
          update_state rx, 'can'
        when "\0"
          print_timing rx
        else
          log rx, 'noise', {'data'=> rx.data}
          nil
        end
        # value returned from above is returned dispatcher
      end
    end

  end
end

if __FILE__ == $0
  server = Radish::RadioServer.new

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-w", "--wangler HOST",
            "Specify an alternate wangler hostname") { |arg|
      server.wangler_uri.host = arg
    }
    opts.on("-p", "--port NUM", Integer,
            "Specify an alternate wangler port") { |arg|
      server.wangler_uri.port = arg
    }
    opts.on("-d", "--debug [LEVEL]", Integer,
            "Specify the debugging level (default 1)") { |arg|
      server.debug_level = arg || 1
    }
    opts.on("--tty DEVICE",
            "Specify a non-default serial device " +
            "[default: #{server.tty}]") { |arg|
      server.tty = arg
    }
  end.parse!

  server.connect
  server.daemonize
end
