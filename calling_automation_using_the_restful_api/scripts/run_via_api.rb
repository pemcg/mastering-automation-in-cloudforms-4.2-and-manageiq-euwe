#!/usr/bin/env ruby
#
# run_via_api
#
# Author:   Peter McGowan (pemcg@redhat.com)
#           Copyright 2015 Peter McGowan, Red Hat
#
# Revision History
#
require 'rest-client'
require 'json'
require 'optparse'

begin
  options = {
            :server     => nil,
            :username   => nil,
            :password   => nil,
            :domain     => nil,
            :namespace  => nil,
            :class      => nil,
            :instance   => nil,
            :parameters => []
            }
  parser = OptionParser.new do|opts|
    opts.banner = "Usage: run_via_api.rb [options]"
    opts.on('-s', '--server server', 'CloudForms server to connect to') do |server|
      options[:server] = server
    end
    opts.on('-u', '--username username', 'Username to connect as') do |username|
      options[:username] = username
    end
    opts.on('-p', '--password password', 'Password') do |password|
      options[:password] = password
    end
    opts.on('-d', '--domain ', 'Domain') do |domain|
      options[:domain] = domain
    end
    opts.on('-n', '--namespace ', 'Namespace') do |namespace|
      options[:namespace] = namespace
    end
    opts.on('-c', '--class ', 'Class') do |klass|
      options[:class] = klass
    end
    opts.on('-i', '--instance ', 'Instance') do |instance|
      options[:instance] = instance
    end
    opts.on('-P', '--parameter <key,value>', Array, 'Parameter (key => value pair) for the instance') do |parameters|
      unless parameters.length == 2
        puts "Parameter argument must be key,value list"
        exit!
      end
      options[:parameters].push parameters
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
  if options[:domain].nil?
    puts "Domain must be specified"
    exit!
  end
  if options[:namespace].nil?
    puts "Namespace must be specified"
    exit!
  end
  if options[:class].nil?
    puts "Class must be specified"
    exit!
  end
  if options[:instance].nil?
    puts "Instance to run must be specified"
    exit!
  end

  api_uri = "https://#{server}/api"
  #
  # Turn parameter list into hash
  #
  parameter_hash = {}
  options[:parameters].each do |parameter|
    parameter_hash[parameter[0]] = parameter[1]
  end
  
  message = "Running automation method "
  message += "#{options[:namespace]}/#{options[:class]}/#{options[:instance]}"
  message += " using parameters: "
  message += "#{parameter_hash.inspect}"
  puts message
  #
  # Get an authentication token
  #
  url = URI.encode(api_uri + '/auth')
  rest_return = RestClient::Request.execute(method:      :get,
                                              url:        url,
                                              :user       => username,
                                              :password   => password,
                                              :headers    => {:accept => :json},
                                              verify_ssl: false)
  auth_token = JSON.parse(rest_return)['auth_token']
  raise "Couldn't get an authentication token" if auth_token.nil?
  
  post_params = {
    :version => '1.1',
    :uri_parts => {
      :namespace => "#{options[:domain]}/#{options[:namespace]}",
      :class => options[:class],
      :instance => options[:instance]
    },
    :parameters => parameter_hash,
    :requester => {
      #:auto_approve => false
      :auto_approve => true
    }
  }.to_json
  #
  # Issue the automation request
  #
  url = URI.encode(api_uri + '/automation_requests')
  rest_return = RestClient::Request.execute(method:     :post,
                                            url:        url,
                                            :headers    => {:accept        => :json, 
                                                            'x-auth-token' => auth_token},
                                            :payload    => post_params,
                                            verify_ssl: false)
  result = JSON.parse(rest_return)
  #
  # get the request ID
  #
  request_id = result['results'][0]['id']
  #
  # Now we have to poll the automate engine to see when the request_state has changed to 'finished'
  #
  url = URI.encode(api_uri + "/automation_requests/#{request_id}")
  rest_return = RestClient::Request.execute(method:     :get,
                                            url:        url,
                                            :headers    => {:accept        => :json, 
                                                            'x-auth-token' => auth_token},
                                            verify_ssl: false)
  result = JSON.parse(rest_return)
  request_state = result['request_state']
  until request_state == "finished"
    puts "Checking completion state..."
    rest_return = RestClient::Request.execute(method:     :get,
                                              url:        url,
                                              :headers    => {:accept        => :json, 
                                                              'x-auth-token' => auth_token},
                                              verify_ssl: false)
    result = JSON.parse(rest_return)
    request_state = result['request_state']
    sleep 3
  end
  puts "Request exited with status: #{result['status']}"
  if result['status'].downcase != 'ok'
    puts "Returned message: #{result['message']}"
  end
  unless result['options']['return'].nil?
    puts "Returned results: #{result['options']['return'].inspect}"
  end
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
