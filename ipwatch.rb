#!/usr/bin/env ruby

require 'json'
require 'httparty'
require 'slack-notifier'

STATE_PATH = "/tmp/ipwatch.json"

$stdout.sync = true

class Watcher

  def initialize(config_file)
    @config = YAML.load_file(config_file)
    puts "Config: #{@config.inspect}"
    @location = @config['location']
    @state = {}
    @notifier = Slack::Notifier.new @config['slack_webhook_url']
  end

  def load_last_state
    return if File.exists?(STATE_PATH)
    state_data = File.read(STATE_PATH)
    state = JSON.parse(STATE_PATH)
  end

  def check_ip
    record = @config['dns_record']

    # get current ip
    resp = HTTParty.get("https://api.ipify.org?format=json")
    needs_update = false
    if resp.code == 200
      jd = JSON.parse(resp.body)
      ip = jd['ip']
      # get dns ip
      entry = get_dns_entry(record)
      if entry
        puts "Record found: #{entry.inspect}"
      else
        puts "Record not found for #{record}"
      end
      if entry.nil? || entry['value'] != ip
        needs_update = true
        notify("#{@location} IP has changed to #{ip}")
        update_dns(record, ip, entry)
        notify("DNS record #{record} successfully updated.")
        @state['last_ip'] = ip
        @state['last_checked_at'] = Time.now
        puts "DNS entry #{record} updated to #{ip}."
      end
    else
      puts "Could not determine IP"
    end
  rescue => ex
    puts ex.inspect
    if needs_update
      notify("DNS record #{record} could not be updated (#{ex.message}).")
    end
  end

  def update_dns(record, ip, entry)
    remove_dns_entry(entry) if entry
    add_dns_record(record, ip)
    return true
  end

  def get_dns_entry(record)
    key = @config['dreamhost_api_key']
    # get record
    url = "https://api.dreamhost.com/?key=#{key}&format=json&cmd=dns-list_records"
    resp = HTTParty.get(url)
    #puts resp.body
    rd = JSON.parse(resp.body)
    rec = rd['data'].select{|r| r['record'] == record}.first
    return rec
  end

  def remove_dns_entry(entry)
    key = @config['dreamhost_api_key']
    # remove record 
    url = "https://api.dreamhost.com/?key=#{key}&format=json&cmd=dns-remove_record&type=A&record=#{entry['record']}&value=#{entry['value']}"
    resp = HTTParty.get(url)
    #puts resp.body
    rd = JSON.parse(resp.body)
    if rd['result'] == 'success'
      return true
    else
      raise rd['data']
    end
  end

  def add_dns_record(record, ip)
    key = @config['dreamhost_api_key']
    # add record 
    url = "https://api.dreamhost.com/?key=#{key}&format=json&cmd=dns-add_record&type=A&record=#{record}&value=#{ip}&comment=IPWatch"
    #puts url
    resp = HTTParty.get(url)
    #puts resp.body
    rd = JSON.parse(resp.body)
    if rd['result'] == 'success'
      return true
    else
      raise rd['data']
    end
  end

  def notify(msg)
    @notifier.ping msg
  end

  def run
    loop do
      check_ip
      sleep 60*60
    end
  end
end

watcher = Watcher.new(ARGV[0])
watcher.run
