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
  class ThreadedQueue < Array
    def initialize(*args, &block)
      @thread_running = false
      @handler_proc = block
      super(*args)
    end

    def <<(*args)
      rv = super(*args)

      Thread.critical = true
      if !@thread_running
        @thread_running = true
        Thread.critical = false

        Thread.new do
          begin
            Thread.critical = true
            while !empty?
              Thread.critical = false
              @handler_proc.call
              Thread.critical = true
            end
          ensure
            @thread_running = false
            Thread.critical = false
          end
        end  # Thread.new
      end  # if
      Thread.critical = false

      return rv
    end
  end
end
