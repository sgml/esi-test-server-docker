# frozen_string_literal: true

# Copyright 2017 Akamai Technologies, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'minitest/autorun'
require 'httparty'
require 'open3'

module Minitest
  class Test
    IMAGE_NAME = 'akamaiesi/ets-docker:latest'
    LOCAL_MOUNT_DIR = "#{File.expand_path(File.dirname(__FILE__))}/../html"
    REMOTE_MOUNT_DIR = '/opt/akamai-ets/virtual/localhost/docs'
    MAX_PORT_WAIT = 5 # seconds
    HOST_HOSTNAME = 'localhost'
    DEFAULT_APACHE_HOST = 'localhost'
    INTERNAL_PORT = 80

    def start_containers(args = nil, wait = true)
      docker_cmd = 'docker run -d -P ' \
          "-v #{LOCAL_MOUNT_DIR}:#{REMOTE_MOUNT_DIR} #{IMAGE_NAME} #{args.nil? ? '' : args}"
      puts "Docker run command: #{docker_cmd}"

      stdout_stderr, status = Open3.capture2(docker_cmd)
      unless status.success?
        msg = "Docker run exited with code #{status.to_i} and output:\n#{stdout_stderr}"
        puts msg
        fail msg
      end
      @container_id = stdout_stderr.delete("\n")

      @esi_port = `docker port #{@container_id}`.scan(/#{INTERNAL_PORT}.+:(\d+)/)[0][0]

      return unless wait
      wait_for_port_or_fail(HOST_HOSTNAME, @esi_port)
    rescue => e
      if `docker inspect -f {{.State.Running}} #{@container_id}`.start_with? 'false'
        puts "Container #{@container_id} wasn't running after " \
                      'port check failure.'
        puts "Container exit code was: #{`docker inspect -f {{.State.ExitCode}} #{@container_id}`}"
        puts "Container output was:\n#{`docker logs #{@container_id}`}"
      end
      throw e
    end

    def teardown
      `docker kill #{@container_id}`
      `docker rm #{@container_id}`
    rescue => e
      puts 'Error in teardown:'
      puts e
    end

    ##
    # Waits for the ports to be open, with retries in between
    def wait_for_port_or_fail(host, port)
      result = false
      3.times do
        # ensure we wait a minimum between retries
        start_time = Time.now
        result = check_port_for_http_response(host, port)
        check_time = Time.now - start_time
        break if result

        if check_time < 10
          sleep 10 - check_time
        end
      end
      return if result
      fail 'Timeout waiting for port to be open.'
    end

    def check_port_for_http_response(host, port)
      url = "http://#{host}:#{port}"
      response = HTTParty.get(url, timeout: MAX_PORT_WAIT)
      return !response.code.nil?
    rescue
      false
    end

    def string_has_no_esi_tags?(str)
      !(str =~ /<esi:/)
    end

    def container_stdout
      stdout, = Open3.capture3("docker logs #{@container_id}")
      stdout
    end

    def container_stderr
      _, stderr, = Open3.capture3("docker logs #{@container_id}")
      stderr
    end
  end
end
