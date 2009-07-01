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
  class Daemon

    BASEDIR = "/var/cache/radish/" # must end in /

    attr_accessor :logfile
    attr_accessor :verbose

    def initialize
      self.verbose = true
      self.logfile = default_logfile
      # so that other people can restart the services
      # make sure logfiles and images are group writable
      File.umask(002)
    end

    def default_logfile
      "%s%s.log" % [ BASEDIR, self.class.to_s.sub(/.*::/,'') ]
    end

    # filename to store the pid of this daemon after fork
    def pidfile(runclass = self.class)
      "%s%s.pid" % [ BASEDIR, runclass.to_s.sub(/.*::/,'') ]
    end

    def writepid
      File.open(pidfile,'w') { |f| f.puts $$ }
    end

    # returns the last saved process id for a given class
    # or nil if pid file is missing
    def readpid(runclass = self.class)
      File.read(pidfile(runclass)).to_i rescue nil
    end

    # returns true if a given process id (pid) hasn't died
    def still_running?(pid)
      Process.kill 0, pid rescue false
    end

    def redirect_to_logfile
      f = File.open logfile, 'a'
      null = File.open '/dev/null', 'w'
      STDOUT.reopen f
      STDOUT.sync = true
      STDERR.reopen f
      STDERR.sync = true
      STDIN.reopen null
    end

    def daemonize
      oldpid = readpid

      if oldpid && still_running?(oldpid)
        raise "Already running on pid #{oldpid}"
      end

      pid = fork do
        redirect_to_logfile
        $0 = self.class.to_s
        writepid
        run
      end
      puts "forked [#{pid}] see output at #{logfile}" if verbose
      return pid
    end

  end
end
