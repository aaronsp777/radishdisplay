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

module Radish
  class Connection
    DEFAULT_BPS  = 57600

    class NoDevice < RuntimeError; end

    attr_accessor :fh
    attr_accessor :tty

    # finds the first usb serial device attached to the system
    def self.default_port
      ports = Dir.glob "/dev/ttyUSB*" # Linux
      ports += Dir.glob "/dev/ttyAMA*" # Raspberry Pi
      ports += Dir.glob "/dev/cu.usbserial-*" # Mac OS X
      raise NoDevice, 'Ensure Wongle is connected', caller if ports.empty?
      return ports.first
    end

    def self.default_connection
      new default_port
    end

    #
    # setup connection to a Wongle
    #
    # you may override the default baud (bps).
    def initialize(tty, bps = DEFAULT_BPS)
      self.fh = File.open tty, 'r+'
      self.fh.sync = true
      self.tty = tty
      setbaud(bps) if bps
      # Drain serial buffer. There's a nonzero-timeout to allow packets
      # buffered by the XBee to be flushed.
      while select([self.fh], nil, nil, 0.25)
        puts "Flushed %d bytes" % self.fh.sysread(8192).length
      end
    end

    def setbaud(bps)
      `stty #{bps} -echo raw crtscts < #{tty}` # set baud rate
    end

    def write(*args)
      fh.write(*args)
    end

    # Differs slightly from normal read: This guarantees that all bytes are
    # read.
    def read(length)
      data = ""
      while data.length < length
        result = fh.read(length - data.length)
        raise EOFError if result.nil?
        data << result
      end
      data
    end

  end
end
