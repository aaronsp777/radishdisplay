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
require 'thread.rb'

module Radish
  class ThreadedQueue < Array
    def initialize(*args, &block)
      @thread_running = false
      @handler_proc = block
      @mutex = Mutex.new
      super(*args)
    end

    def <<(*args)
      rv = super(*args)

      @mutex.lock
      if !@thread_running
        @thread_running = true
        @mutex.unlock

        Thread.new do
          begin
            @mutex.lock
            while !empty?
              @mutex.unlock
              begin
                @handler_proc.call
              ensure
                @mutex.lock
              end
            end
          ensure
            @thread_running = false
            @mutex.unlock
          end
        end  # Thread.new
      else
        @mutex.unlock
      end  # if

      return rv
    end
  end
end
