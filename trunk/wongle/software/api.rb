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

require 'threaded_queue'

module Radish
  module Ascii
    NUL = "\000" # padding to flush xbee output buffer
    STX = "\002" # server start tansfer
    ETX = "\003" # server end transfer
    EOT = "\004" # End of Transfer (currently not used)
    ACK = "\006" # receive success
    NAK = "\025" # receive failure
    SYN = "\026" # begin receiving (currently not used)
    CAN = "\030" # stop all communications and retry later
  end

  class Api
    AT_COMMAND = 0x08
    AT_RESPONSE = 0x88
    RECEIVE_PACKET = 0x80
    TRANSMIT_REQUEST = 0x00
    TRANSMIT_STATUS = 0x89
    START_BYTE = 0x7E

    class AtResponse
      IDENTIFIER = AT_RESPONSE
      attr_reader :command, :status, :value
      def read(data)
        @frame_id, @command, @status, @value = data.unpack('xCa2Ca*')
      end
    end

    class RxPacket
      IDENTIFIER = RECEIVE_PACKET
      attr_reader :address, :signalstrength, :options, :data
      def read(data)
        @address, @signalstrength, @options, @data = data.unpack('xH16CCa*')
      end
    end

    class StatusPacket
      IDENTIFIER = TRANSMIT_STATUS
      attr_reader :frame_id, :status
      def read(data)
        @frame_id, @status = data.unpack('xCC')
      end
    end

    # Contains the data needed to make a response to a Radish.
    # Return one of these from the dispatch block.
    class Response
      # Whether the data should be sent raw, without massaging it into the
      # proper format.
      attr_accessor :raw

      # How many packets to retry before giving up on the transmission.
      attr_accessor :retries

      # Whether this response should preempt any others in the queue. (Useful
      # for a quick cancel.)
      attr_accessor :preempt

      # A list of data to be sent in each phase. All the packets in one phase
      # are guaranteed to be acted upon before any packets in later phases. The
      # format is a list of lists of strings, where the strings are data
      # packets, and the list at index N is the data for phase N.
      attr_reader :phase_data

      # The number of seconds the radish should sleep after receiving this
      # response.
      attr_reader :sleep_time

      # Where this response will be sent to
      attr_accessor :address

      # Optional callback to be called if the number of retries is exceeded
      attr_accessor :failure_callback

      # Set to true to enable debugging on the response
      attr_accessor :debug

      def initialize(phase_data, sleep_time)
        @phase_data = phase_data
        @sleep_time = sleep_time
        @raw = false
        @retries = 0
        @preempt = false
        @failure_callback = proc {}
        @phase = 0
        @packet = 0
        @confirmed_seq_num = 0
        @phase_offsets = [0]
        for phase in @phase_data
          @phase_offsets << @phase_offsets[-1] + phase.length
        end
        @num_packets = @phase_offsets.pop
        # Handler queue is the queue of packets that are "in-flight." (It's
        # actually a queue of their ack-handling procs, thus the name.)
        @handler_queue = []
      end

      def length
        length = 0

        for phase_list in @phase_data
          for packet in phase_list
            length += packet.length
            length += 2 if !@raw
          end
        end

        return length + 2
      end

      # Indicates whether this response is in a state where there is data ready
      # to send.
      def packet_ready?
        if done?
          return false
        end

        if @raw
          return true
        end

        return @phase < @phase_data.length
      end

      # Indicates whether this response is completely finished, i.e. all data
      # sent successfully.
      def done?
        if retries < 0
          return true
        end

        if @raw
          return @phase > 0
        end

        return @confirmed_seq_num >= @num_packets
      end

      # This is the logic for what to do when we get an radio packet ack (or
      # lack of ack.)
      def handler_func(status, ack_canceled, this_handler,
                       seq_byte, this_phase, this_packet)
        # We need a self-destruct button. The proc will take care of setting
        # ack_canceled.
        if status == -1
          return
        end

        if @debug
          puts ("0x%0x " % object_id) + "Status #{status} recieved for " +
               (ack_canceled ? 'canceled ' : '') + "packet #{seq_byte}"
        end

        if ack_canceled
          return
        end

        # This is a bad case - the wongle's XBee "missed" sending us any
        # kind of status update for a packet, and we only found out when it
        # sent a status update for a later packet. It shouldn't ever happen,
        # but it does when the signal gets flaky.
        #
        # Solution: Create a synthetic NAK for the missed packet.
        if this_handler != @handler_queue[0]
          return @handler_queue[0].call(1)
        end

        # From here on out, we know we're the proper packet
        if status == 0
          if seq_byte != @confirmed_seq_num
            puts "Horrible bad thing! We got an out-of-order ACK when " +
                 "that should be impossible!"
            return
          end

          @confirmed_seq_num += 1
          @handler_queue.shift
        else  # The radish didn't get this packet, at least AFAICT.
          @phase = this_phase
          @packet = this_packet
          @retries -= 1
          # Seal all entrances and exits! Close all shops in the mall!
          # Cancel the three-ring circus!
          @handler_queue.each { |x| x.call(-1) }
          @handler_queue = []
        end
      end

      # Returns a pair of [data, callback]. The data is the next packet to send,
      # and the callback is called to return status of whether the packet was
      # sent successfully.
      def next
        if !packet_ready?
          return nil
        end

        if @raw
          p = @phase_data[@phase][@packet]

          @packet += 1
          if @packet >= @phase_data[@phase].length
            # Tack on an extra packet for the sleep info
            if p.length > 98
              @phase_data[@phase] = @phase_data[@phase].dup << ''
            else
              p = p.dup << sleep_bytes
              @phase = 1
            end
          end

          return p, proc {}
        end

        this_phase = @phase
        this_packet = @packet
        p = @phase_data[@phase][@packet]
        seq_byte = @packet + @phase_offsets[@phase]

        @packet += 1
        if @packet >= @phase_data[@phase].length
          @phase += 1
          @packet = 0
        end

        header = Ascii::STX
        if @phase >= @phase_data.length
          # Tack on the sleep info. There better be room.
          p = p + sleep_bytes
          header = Ascii::ETX
        end

        if @debug
          puts "0x%0x Sending packet #{seq_byte}" % object_id
        end

        ack_canceled = false

        ack_handler = nil  # Define this so that the proc binds on it
        ack_handler = proc { |status|
          handler_func(status, ack_canceled, ack_handler,
                       seq_byte, this_phase, this_packet)
          # We should only take action on these once. After that, they're
          # dead.
          ack_canceled = true
        }

        @handler_queue << ack_handler
        return [header.bytes.first, seq_byte, p].pack('CCa*'), ack_handler
      end

      # Takes a sleep time in seconds and converts it to a ghetto-point
      # representation for the radish.
      def sleep_bytes
        # The format is two bytes. First byte is a loop count of how many times
        # to sleep. The second byte is an exponent for the delay. The exponent
        # has five added to it, i.e. the prescaler ranges from 2^5 when exponent
        # is 0 to (max) 2^23 when it's 18.

        # Convert to "ticks" of the minimum timeslice - 32 / 31kHz
        ticks = @sleep_time * (31000.0 / 32)
        exponent = 0

        # 256 is the next representable tick (at a higher exponent), so the
        # rounding point is 255.5
        while (exponent <= 18 and ticks >= 255.5)
          ticks /= 2.0
          exponent += 1
        end

        ticks = ticks.round
        if ticks > 255
          ticks = 255
        end

        return [ticks, exponent].pack('CC')
      end  # sleep_bytes
    end  # Response

    @packet_classes = {}
    for packet_class in constants
      packet_class = const_get(packet_class)
      next unless packet_class.is_a? Class
      next unless packet_class.const_defined?('IDENTIFIER')

      id = packet_class.const_get('IDENTIFIER')
      @packet_classes[id] = packet_class
    end

    # Class functions
    def self.checksum(data)
      sum = 0
      data.each_byte do |i|
        sum += i
      end
      return 0xFF - (sum & 0xFF)
    end

    def self.parse_data(data)
      packet_class = @packet_classes[data.bytes.first]
      if !packet_class
        puts "Received packet of unknown type #{data.bytes.first}: " +
             data.inspect
        STDOUT.flush
        return nil
      end

      packet = packet_class.new
      packet.read(data)
      return packet
    end

    # Used to create a cancel response
    def self.cancel(sleep_time)
      p = Response.new([[Ascii::CAN]], sleep_time)
      p.raw = true
      p.preempt = true
      p
    end

    attr_accessor :debug

    def initialize(connection)
      @connection = connection
      @debug = false
      @response_queue = ThreadedQueue.new(&method(:writer_func))
      @writer_queue = []
      @writer_running = false
      @callbacks = [nil] * 256
      @seq_num = 1
    end

    def writer_func
      if @debug
        puts 'Started writer thread'
        STDOUT.flush
      end

      loop do
        # Cleanup old responses
        @writer_queue.delete_if {|resp| resp.done?}

        if @debug.is_a?(Fixnum) and @debug > 1
          puts @writer_queue.inspect
          STDOUT.flush
        end

        while !@response_queue.empty?
          item = @response_queue.slice!(0)
          if item.is_a? StatusPacket
            callback = @callbacks[item.frame_id]
            if !callback
              puts "Recieved status for frame #{item.frame_id}, " +
                   "but we don't remember that packet!"
              STDOUT.flush
            else
              if @debug
                puts "Updating status for frame #{item.frame_id}"
                STDOUT.flush
              end
              callback.call(item.status)
            end
          else
            if item.preempt
              @writer_queue.insert(0, item)
            else
              @writer_queue << item
            end
          end  # if
        end  # while

        packet = nil
        for response in @writer_queue
          next unless response.packet_ready?
          packet, callback = response.next

          @callbacks[@seq_num] = callback
          send_packet(
            [TRANSMIT_REQUEST, @seq_num,
            response.address, 0x00, packet].pack('CCH16Ca*')
          )
          @seq_num = (@seq_num % 255) + 1
          break
        end

        if !packet
          if @debug
            puts 'Writer thread exiting'
            STDOUT.flush
          end
          return
        end
      end  # loop
    end  # writer_func

    def send_packet(data)
      packet = [START_BYTE, data.length, data, Api.checksum(data)].pack('Cna*C')

      if @debug
        puts 'Sending data: ' + packet.inspect
        STDOUT.flush
      end
      @connection.write packet
    end

    def read_api_packet
      packet = nil
      while !packet
        start = @connection.read(1).bytes.first

        if start != START_BYTE
          puts "Expected #{START_BYTE}, got junk byte " +
               "#{start.inspect} from wongle"
          STDOUT.flush
          next
        end

        length = @connection.read(2).unpack('n')[0]

        data = @connection.read(length)
        check = @connection.read(1).bytes.first

        if Api.checksum(data) != check
          puts "Checksum calculated as #{Api.checksum(data)}, but " +
               "should have been #{check}! Packet: #{data.inspect}"
          STDOUT.flush
          next
        end

        packet = Api.parse_data(data)
      end

      return packet
    end

    # never ending loop to service requests from the radio
    # Yields |rxpacket|
    # expects the block to return data to be returned to the
    # client that sent the original request
    def dispatch_loop
      loop do
        packet = read_api_packet
        if packet.is_a? RxPacket
          response = yield packet
          if !response.nil?
            response.address = packet.address
            @response_queue << response
          end
        elsif packet.is_a? StatusPacket
          if packet.status != 0
            puts "Frame #{packet.frame_id} failed to send"
            STDOUT.flush
          end
          @response_queue << packet
        else
          puts "Don't know how to handle this packet: " +
               api.payload.inspect
          STDOUT.flush
        end
      end  # loop
    end  # dispatch_loop

  end  # Api
end  # Radish
