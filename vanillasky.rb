#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'optparse'
require 'dotenv/load'

class VanillaSky
  API_BASE = 'https://bsky.social/xrpc'

  def initialize
    @access_token = nil
    @did = nil
    @days_threshold = 90
    @dry_run = true  # Default to dry run for safety
  end

  def run(args)
    parse_options(args)

    puts "🌌 VanillaSky - Bluesky Post Auto-Deletion Tool"
    puts "============================================="

    authenticate

    if @dry_run
      puts "🔍 DRY RUN MODE - No posts will be deleted"
    end

    posts = fetch_old_posts

    if posts.empty?
      puts "✅ No posts older than #{@days_threshold} days found."
      return
    end

    puts "📋 Found #{posts.length} posts older than #{@days_threshold} days"

    unless @dry_run
      puts "⚠️  This will permanently delete these posts. Continue? (y/N)"
      response = STDIN.gets.chomp.downcase
      unless response == 'y' || response == 'yes'
        puts "❌ Cancelled."
        return
      end
    end

    delete_posts(posts)
  end

  private

  def parse_options(args)
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"

      opts.on("-d", "--days DAYS", Integer, "Delete posts older than DAYS (default: 90)") do |days|
        @days_threshold = days
      end

      opts.on("-n", "--dry-run", "Show what would be deleted without actually deleting (default)") do
        @dry_run = true
      end

      opts.on("-f", "--force", "Actually delete posts (required to disable dry-run mode)") do
        @dry_run = false
      end

      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
    end.parse!(args)
  end

  def authenticate
    handle = ENV['BLUESKY_HANDLE']
    password = ENV['BLUESKY_APP_PASSWORD']

    # Fall back to interactive input if not in environment
    if handle.nil? || handle.empty?
      print "Enter your Bluesky handle (e.g., user.bsky.social): "
      handle = STDIN.gets.chomp
    end

    if password.nil? || password.empty?
      print "Enter your app password: "
      password = STDIN.noecho(&:gets).chomp
      puts
    end

    uri = URI("#{API_BASE}/com.atproto.server.createSession")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = {
      identifier: handle,
      password: password
    }.to_json

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      @access_token = data['accessJwt']
      @did = data['did']
      puts "✅ Successfully authenticated as #{handle}"
    else
      puts "❌ Authentication failed: #{response.body}"
      exit 1
    end
  end

  def fetch_old_posts
    cutoff_date = Date.today - @days_threshold
    old_posts = []
    cursor = nil

    puts "🔍 Scanning for posts older than #{cutoff_date}..."

    loop do
      uri = URI("#{API_BASE}/com.atproto.repo.listRecords")
      params = {
        repo: @did,
        collection: 'app.bsky.feed.post',
        limit: 100
      }
      params[:cursor] = cursor if cursor

      uri.query = URI.encode_www_form(params)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"

      response = http.request(request)

      if response.code != '200'
        puts "❌ Failed to fetch posts: #{response.body}"
        break
      end

      data = JSON.parse(response.body)

      data['records'].each do |record|
        created_at = DateTime.parse(record['value']['createdAt'])
        if created_at.to_date <= cutoff_date
          old_posts << {
            uri: record['uri'],
            created_at: created_at,
            text: record['value']['text']&.slice(0, 100)
          }
        end
      end

      cursor = data['cursor']
      break unless cursor

      print "."
    end

    puts
    old_posts
  end

  def delete_posts(posts)
    deleted_count = 0

    posts.each_with_index do |post, index|
      if @dry_run
        puts "[DRY RUN] Would delete: #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
      else
        if delete_post(post[:uri])
          deleted_count += 1
          puts "🗑️  Deleted (#{index + 1}/#{posts.length}): #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
        else
          puts "❌ Failed to delete: #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
        end

        # Rate limiting - sleep briefly between deletions
        sleep(0.5)
      end
    end

    if @dry_run
      puts "🔍 DRY RUN: Would have deleted #{posts.length} posts"
    else
      puts "✅ Successfully deleted #{deleted_count} out of #{posts.length} posts"
    end
  end

  def delete_post(post_uri)
    # Extract the rkey from the URI
    rkey = post_uri.split('/').last

    uri = URI("#{API_BASE}/com.atproto.repo.deleteRecord")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      repo: @did,
      collection: 'app.bsky.feed.post',
      rkey: rkey
    }.to_json

    response = http.request(request)
    response.code == '200'
  end
end

# Only run if this file is executed directly
if __FILE__ == $0
  VanillaSky.new.run(ARGV)
end
