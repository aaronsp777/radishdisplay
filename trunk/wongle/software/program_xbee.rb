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

require 'expect'
require 'optparse'
require 'connection'

module Radish
  class Radio

    attr_accessor :conn
    attr_accessor :port

    def initialize(tty)
      self.conn = Connection.new tty
    end

    def program
      determine_baud
      send_cmd "ATRE\r"
      puts "sleeping 10"
      sleep 10
      determine_baud
      serial = get_serial
      send_cmd "ATBD6\r"
      send_cmd "ATSM1\r"
      send_cmd "ATMYFFFF\r"
      send_cmd "ATWR\r"
      send_cmd "ATCN\r"
      puts "Serial is: #{serial}"
    end

    def program_wongle
      determine_baud
      send_cmd "ATRE\r"
      puts "sleeping 10"
      sleep 10
      determine_baud
      send_cmd "ATBD6\r"
      send_cmd "ATSM0\r"
      send_cmd "ATAP1\r"
      send_cmd "ATWR\r"
      send_cmd "ATCN\r"
    end

    def factory_reset
      determine_baud
      send_cmd "ATRE\r"
      send_cmd "ATWR\r"
      send_cmd "ATCN\r"
    end

    # returns true if "OK\r" is recvd
    # raises if not
    def send_cmd(cmd = "AT\r", exp = /OK\r/)
      puts "sending: #{cmd.inspect}"
      conn.write cmd
      resp = conn.fh.expect(exp, 1) or raise 'WrongOrMissingResponse'
      return resp[0]
    end

    def get_serial
      sh = send_cmd "ATSH\r", /[0-9A-F]+\r/
      sl = send_cmd "ATSL\r", /[0-9A-F]+\r/
      sprintf "%08X%08X", sh.hex, sl.hex
    end

    # trys all baud rates at most twice
    # raises exception on failure
    def determine_baud
      [9600, 57600, 115200, 9600, 57600, 115200].each do |bps|
        puts "trying baud: #{bps}"
        conn.setbaud(bps)
        sleep 0.2
        conn.write '+++'
        sleep 0.2
        if conn.fh.expect(/OK\r/, 1)
          puts "found"
          return
        else
          puts "no answer"
        end
      end
      raise 'no response for any baud'
    end

  end

end

if __FILE__ == $0

  opts = OptionParser.new
  $factory = false
  $wongle  = false
  tty      = nil
  opts.on('--factory', 'Factory Reset') { |v| $factory = v }
  opts.on('--wongle',  'Server Wongle') { |v| $wongle = v }
  opts.on('--tty DEVICE', "Serial line to use [default: #{tty}]") { |v| tty = v }
  opts.parse! ARGV
  tty ||= Radish::Connection.default_port
  radio = Radish::Radio.new tty
  if $factory
    radio.factory_reset
  elsif  $wongle
    radio.program_wongle
  else
    radio.program
  end
end

