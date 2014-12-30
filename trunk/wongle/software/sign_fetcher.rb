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
require 'net/https'
require 'uri'
require 'yaml'
require 'time'

module Radish
  class NoResponse < RuntimeError; end
  class MissingImage < RuntimeError; end
  class WrongImageSize < RuntimeError; end
  class NotModified < RuntimeError; end
  class SleepInterrupted < RuntimeError; end
  class SignFetcher < Daemon

    MAX_AGE = 300 # how often to build new signs
    IMAGE_SIZE_BYTES = 9611

    def log(string)
      puts "#{Time.now.xmlschema} #{string}"
    end

    def download_image(url, lastmod)
      uri = URI.parse url
      http = Net::HTTP.new uri.host, uri.port
      if uri.scheme == 'https'
        http.use_ssl = true # enable SSL/TLS
        if File.directory? '/etc/ssl/certs'
          http.ca_path = '/etc/ssl/certs'
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
      end
      http.read_timeout = 120
      header = {}
      header['If-Modified-Since'] = lastmod.httpdate if lastmod
      res = nil
      http.start do
        res = http.request_get uri.request_uri, header
      end
      raise NoResponse if res.nil?
      raise NotModified if res.is_a? Net::HTTPNotModified
      return res.body
    end

    def write_image(new_data, filename)
      filename_tmp = BASEDIR + "tmp#{$$}"

      # build the new image and grab the old one off of the disk
      # Providing number of bytes forces it to binary mode read.
      old_data = File.read(filename, IMAGE_SIZE_BYTES) rescue nil

      # don't touch the files if nothings changed
      if new_data == old_data
        log "identicial" if verbose
        return
      end
      
      # write image
      fo = File.open filename_tmp, 'w'
      fo.write new_data
      fo.close

      # move it into place to avoid race condition
      File.rename filename_tmp, filename

      log "updated" if verbose

    end

    def do_one_sign(mac, url)
      begin

        filename = BASEDIR + mac + '.pbm'

        # last modified time on the file
        lastmod = File.exists?(filename) ?
            File.mtime(filename) : nil

        pbm = begin
          download_image url, lastmod 
        rescue NotModified
          log "not modified" if verbose
          return
        end
        raise MissingImage if pbm.nil? or pbm == ""
        raise WrongImageSize if pbm.to_s.length != IMAGE_SIZE_BYTES
        write_image pbm, filename

      rescue => e
        STDERR.printf "%s failed: %s\n", mac, e.inspect
      end
    end

    def feedurls
      # if file is corrupted or missing,
      # skip this pass for now
      YAML.load(File.read(BASEDIR + 'feedurls')) rescue {}
    end

    def run
      Signal.trap('HUP') { raise SleepInterrupted }
      while true
        feedurls.each do |mac, url|
          log "#{mac}: fetch #{url}" if verbose
          do_one_sign mac, url
        end
        log "sleeping" if verbose
        begin
          sleep MAX_AGE
        rescue SleepInterrupted
          log "Early Wakeup" if verbose
        end
      end
    end

  end
end

if __FILE__ == $0
  Radish::SignFetcher.new.daemonize
end
