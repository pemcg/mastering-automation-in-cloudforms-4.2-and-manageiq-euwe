#!/usr/bin/env ruby
#
# service_via_api
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
            :catalog       => nil,
            :template      => nil,
            :wait_time     => nil,
            :dialog_option => []
            }
  parser = OptionParser.new do|opts|
    opts.banner = "Usage: service_via_api.rb [options]"
    opts.on('-s', '--server server', 'CloudForms server to connect to') do |server|
      options[:server] = server
    end
    opts.on('-u', '--username username', 'Username to connect as') do |username|
      options[:username] = username
    end
    opts.on('-p', '--password password', 'Password') do |password|
      options[:password] = password
    end
    opts.on('-c', '--catalog name', 'Service Catalog Name') do |catalog|
      options[:catalog] = catalog
    end
    opts.on('-t', '--template name', 'Service Template Name') do |template|
      options[:template] = template
    end
    opts.on('-w', '--wait seconds', 'Wait time for service completion in seconds') do |wait|
      options[:wait_time] = wait
    end
    opts.on('-o', '--dialog_option <key,value>', Array, 'Parameter (key => value pair) for the service') do |dialog_option|
      unless dialog_option.length == 2
        puts "Dialog Option argument must be key,value list"
        exit!
      end
      options[:dialog_option].push dialog_option
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
  if options[:wait_time].nil?
    wait_time = 300
  else
    wait_time = options[:wait_time].to_i
  end
  if options[:catalog].nil?
    puts "Catalog name must be specified"
    exit!
  end
  if options[:template].nil?
    puts "Service Template name must be specified"
    exit!
  end

  api_uri = "https://#{server}/api"
  SLEEP_INTERVAL = 30

  #
  # Turn dialog options list into resource hash
  #
  resource_hash = {}

  options[:dialog_option].each do |dialog_option|
    resource_hash[dialog_option[0]] = dialog_option[1]
  end
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
  #
  # Get the service catalog, matching the name that we're after
  #
  catalog_id = nil
  url = URI.encode(api_uri + "/service_catalogs?expand=resources&attributes=id,href&filter[]=name=#{options[:catalog]}")
  rest_response = RestClient::Request.execute(method:     :get,
                                              url:        url,
                                              :headers    => {:accept        => :json, 
                                                              'x-auth-token' => auth_token},
                                              verify_ssl: false)
  service_catalog = JSON.parse(rest_response)
  catalog_id = service_catalog['resources'][0]['id']
  raise "Can't find service catalog with name #{options[:catalog]}" if catalog_id.nil?
  catalog_href = service_catalog['resources'][0]['href']
  
  url = URI.encode(catalog_href + "/service_templates?expand=resources&attributes=id&filter[]=name=#{options[:template]}")
  rest_response = RestClient::Request.execute(method:     :get,
                                              url:        url,
                                              :headers    => {:accept        => :json, 
                                                              'x-auth-token' => auth_token},
                                              verify_ssl: false)
  template_details = JSON.parse(rest_response)
  template_id = template_details['resources'][0]['id']
  raise "Can't find service template with name #{options[:template]}" if template_id.nil?
  
  message = "Requesting service \'#{options[:template]}\' using dialog options #{resource_hash.inspect}"
  puts message
  
  resource_hash['href'] = URI.encode(api_uri + "/service_templates/#{template_id}")
  post_params = {
    "action"   => "order",
    "resource" => resource_hash
  }.to_json
  #
  # Issue the service request
  #
  url = URI.encode(api_uri + "/service_catalogs/#{catalog_id}/service_templates")
  rest_response = RestClient::Request.execute(method:     :post,
                                              url:        url,
                                              :headers    => {:accept        => :json, 
                                                              'x-auth-token' => auth_token},
                                              :payload    => post_params,
                                              verify_ssl: false)
  result = JSON.parse(rest_response)
  #
  # get the request ID
  #
  request_id = result['results'][0]['id']
  puts "Service request accepted, Request ID: #{request_id}"
  #
  # Now we have to poll the automate engine to see when the request_state has changed to 'finished'
  #
  url = URI.encode(api_uri + "/service_requests/#{request_id}")
  rest_return = RestClient::Request.execute(method:     :get,
                                            url:        url,
                                            :headers    => {:accept        => :json,
                                                            'x-auth-token' => auth_token},
                                            verify_ssl: false)
  result = JSON.parse(rest_return)
  request_state = result['request_state']
  wait_time_remaining = wait_time
  timed_out = false
  until request_state == "finished"
    puts "Checking completion state..."
    rest_return = RestClient::Request.execute(method: :get,
                                              url:        url,
                                              :headers    => {:accept        => :json,
                                                              'x-auth-token' => auth_token},
                                              verify_ssl: false)
    result = JSON.parse(rest_return)
    request_state = result['request_state']
    sleep SLEEP_INTERVAL
    wait_time_remaining -= SLEEP_INTERVAL
    if wait_time_remaining <= 0
      timed_out = true
      break
    end
  end
  if timed_out
    puts "Timed out waiting for service completion"
    rc = 2
  else
    # Request is finished check for errors
    rc = 0
    puts "Request exited with status: #{result['status']}"
    if result['status'].downcase != 'ok'
      puts "Returned message: #{result['message']}"
      # Status is not 'ok' - issue rc = 1
      rc = 1
    end
  end
  exit rc
  

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