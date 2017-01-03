#!/usr/bin/env ruby
#
# approve_request_via_api
#
# Author:   Peter McGowan (pemcg@redhat.com)
#           Copyright 2016 Peter McGowan, Red Hat
#
# Revision History
#
require 'rest-client'
require 'json'
require 'optparse'

begin
  options = {
            :server        => nil,
            :username      => nil,
            :password      => nil,
            :request       => nil,
            :reason        => nil,
            :action        => nil,
            }
  parser = OptionParser.new do|opts|
    opts.banner = "Usage: approve_request_via_api.rb [options]"
    opts.on('-s', '--server server', 'CloudForms server to connect to') do |server|
      options[:server] = server
    end
    opts.on('-u', '--username username', 'Username to connect as') do |username|
      options[:username] = username
    end
    opts.on('-p', '--password password', 'Password') do |password|
      options[:password] = password
    end
    opts.on('-i', '--request id', 'Request ID to approve or deny') do |request|
      options[:request] = request
    end
    opts.on('-a', '--action action', '"approve" or "deny"') do |action|
      options[:action] = action
    end
    opts.on('-r', '--reason reason', 'Reason for approving or denying') do |reason|
      options[:reason] = reason
    end
    opts.on('-h', '--help', 'Displays Help') do
      puts opts
      exit!
    end
  end
  parser.parse!
  
  if options[:server].nil?
    server = "myserver"
  else
    server = options[:server]
  end
  if options[:username].nil?
    username = "admin"
  else
    username = options[:username]
  end
  if options[:password].nil?
    password = "smartvm"
  else
    password = options[:password]
  end
  if options[:request].nil?
    puts "Missing request ID (--request option)"
    exit!
  end
  unless ["approve", "deny"].include?(options[:action])
    puts "Must specify either 'approve' or 'deny' for --action"
    exit!
  end
  if options[:reason].nil?
    puts "Missing reason (--reason option)"
    exit!
  end

  api_uri = "https://#{server}/api"

  #
  # Get an authentication token
  #
  url = URI.encode(api_uri + '/auth')
  rest_response = RestClient::Request.execute(method:     :get,
                                              url:        url,
                                              :user       => username,
                                              :password   => password,
                                              :headers    => {:accept => :json},
                                              verify_ssl: false)
  auth_token = JSON.parse(rest_response)['auth_token']
  raise "Couldn't get an authentication token" if auth_token.nil?

  url = URI.encode(api_uri + "/automation_requests/#{options[:request]}")
  #
  # Get the current approval status
  #
  rest_response = RestClient::Request.execute(method:     :get,
                                              url:        url,
                                              :headers    => {:accept        => :json, 
                                                              'x-auth-token' => auth_token},
                                              verify_ssl: false)
  result = JSON.parse(rest_response)
  approval_state = result['approval_state']
  puts "Current approval state for request #{options[:request]} is #{approval_state}"
  #
  # Issue the approve/deny
  #
  post_params = {
    "action" => options[:action],
    "reason" => options[:reason]
  }.to_json
  rest_response = RestClient::Request.execute(method:     :post,
                                              url:        url,
                                              :headers    => {:accept        => :json, 
                                                              'x-auth-token' => auth_token},
                                              :payload    => post_params,
                                              verify_ssl: false)
  result = JSON.parse(rest_response) 
  puts "#{result['message']}"

rescue RestClient::Exception => err
  unless err.response.nil?
    error = err.response
    puts "The REST request failed with code: #{error.code}"
    puts "The response body was:"
    puts JSON.pretty_generate JSON.parse(error.body)
  end
  exit!
rescue => err
  puts "[#{err}]\n#{err.backtrace.join("\n")}"
  exit!
end
