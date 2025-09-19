#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'optparse'
require 'dotenv/load'

class VanillaSky
  VERSION = '0.2'
  API_BASE = 'https://bsky.social/xrpc'

  def initialize
    @access_token = nil
    @did = nil
    @days_threshold = 90
    @dry_run = true  # Default to dry run for safety
    @delete_reposts = false
    @delete_likes = false
    @delete_posts = false
    @delete_replies = false
    @specific_ids = []      # Specific IDs to delete
    @exclude_ids = []       # IDs to exclude from deletion
  end

  def run(args)
    parse_command_and_options(args)

    puts "🌌 VanillaSky - Bluesky Skeet Auto-Delete"
    puts "========================================="

    authenticate

    if @dry_run
      puts "🔍 DRY RUN MODE - Nothing will be deleted"
    end

    if @exclude_ids.any?
      puts "🚫 Excluding #{@exclude_ids.length} IDs from deletion: #{@exclude_ids.join(', ')}"
    end

    if @specific_ids.any?
      posts, replies, reposts, likes = fetch_specific_items(@specific_ids)
    else
      posts = @delete_posts ? fetch_old_posts : []
      replies = @delete_replies ? fetch_old_replies : []
      reposts = @delete_reposts ? fetch_old_reposts : []
      likes = @delete_likes ? fetch_old_likes : []
    end

    if posts.empty? && replies.empty? && reposts.empty? && likes.empty?
      puts "✅ No content older than #{@days_threshold} days found."
      return
    end

    if !posts.empty?
      puts "📋 Found #{posts.length} posts older than #{@days_threshold} days"
    end

    if !replies.empty?
      puts "💬 Found #{replies.length} replies older than #{@days_threshold} days"
    end

    if !reposts.empty?
      puts "🔄 Found #{reposts.length} reposts older than #{@days_threshold} days"
    end

    if !likes.empty?
      puts "👍 Found #{likes.length} likes older than #{@days_threshold} days"
    end

    unless @dry_run
      puts "⚠️  This will permanently delete these items. Continue? (y/N)"
      response = STDIN.gets.chomp.downcase
      unless response == 'y' || response == 'yes'
        puts "❌ Cancelled."
        return
      end
    end

    delete_posts(posts) unless posts.empty?
    delete_replies(replies) unless replies.empty?
    delete_reposts(reposts) unless reposts.empty?
    delete_likes(likes) unless likes.empty?
  end

  private

  def parse_command_and_options(args)
    # Handle version and help before anything else
    if args.include?('--version') || args.include?('-v')
      puts "VanillaSky #{VERSION}"
      exit 0
    end

    if args.include?('--help') || args.include?('-h') || args.empty?
      show_usage
      exit 0
    end

    if args.first.start_with?('-')
      show_usage
      exit 1
    end

    commands = []
    options_start = nil

    args.each_with_index do |arg, i|
      if arg.start_with?('-')
        options_start = i
        break
      elsif %w[posts replies likes reposts].include?(arg)
        commands << arg
      else
        puts "❌ Error: Unknown command '#{arg}'"
        puts "   Valid commands: posts, replies, likes, reposts"
        exit 1
      end
    end

    if commands.empty?
      puts "❌ Error: You must specify what to delete"
      puts "   Valid commands: posts, replies, likes, reposts"
      exit 1
    end

    @delete_posts = commands.include?('posts')
    @delete_replies = commands.include?('replies')
    @delete_likes = commands.include?('likes')
    @delete_reposts = commands.include?('reposts')

    option_args = options_start ? args[options_start..-1] : []
    parse_options(option_args)
  end

  def parse_options(args)
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [posts|likes|reposts] [options]"

      opts.on("-d", "--days DAYS", Integer, "Delete content older than DAYS (default: 90)") do |days|
        @days_threshold = days
      end

      opts.on("-n", "--dry-run", "Show what would be deleted without actually deleting (default)") do
        @dry_run = true
      end

      opts.on("-f", "--force", "Actually delete content (required to disable dry-run mode)") do
        @dry_run = false
      end

      opts.on("--ids ID1,ID2,ID3", Array, "Delete only specific IDs of the specified type (comma-separated rkeys)") do |ids|
        @specific_ids = ids
      end

      opts.on("--exclude-ids ID1,ID2,ID3", Array, "Exclude specific IDs from deletion (comma-separated rkeys)") do |ids|
        @exclude_ids = ids
      end

      opts.on("-h", "--help", "Show this help message") do
        show_usage
        exit
      end

      opts.on("-v", "--version", "Show version") do
        puts "VanillaSky #{VERSION}"
        exit
      end
    end.parse!(args)

    # Validate mutually exclusive options
    if @specific_ids.any? && @exclude_ids.any?
      puts "❌ Error: --ids and --exclude-ids options are mutually exclusive"
      puts "   Use --ids to delete only specific IDs, OR --exclude-ids to exclude IDs from normal deletion"
      exit 1
    end

    if @days_threshold < 0
      puts "❌ Error: Days threshold cannot be negative"
      exit 1
    end
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
        rkey = record['uri'].split('/').last
        is_reply = record['value']['reply'] != nil

        if created_at.to_date <= cutoff_date && !@exclude_ids.include?(rkey) && !is_reply
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

  def fetch_old_replies
    cutoff_date = Date.today - @days_threshold
    old_replies = []
    cursor = nil

    puts "🔍 Scanning for replies older than #{cutoff_date}..."

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
        puts "❌ Failed to fetch replies: #{response.body}"
        break
      end

      data = JSON.parse(response.body)

      data['records'].each do |record|
        created_at = DateTime.parse(record['value']['createdAt'])
        rkey = record['uri'].split('/').last
        is_reply = record['value']['reply'] != nil

        if created_at.to_date <= cutoff_date && !@exclude_ids.include?(rkey) && is_reply
          old_replies << {
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
    old_replies
  end

  def fetch_old_likes
    cutoff_date = Date.today - @days_threshold
    old_likes = []
    cursor = nil

    puts "🔍 Scanning for likes older than #{cutoff_date}..."

    loop do
      uri = URI("#{API_BASE}/com.atproto.repo.listRecords")
      params = {
        repo: @did,
        collection: 'app.bsky.feed.like',
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
        puts "❌ Failed to fetch likes: #{response.body}"
        break
      end

      data = JSON.parse(response.body)

      data['records'].each do |record|
        created_at = DateTime.parse(record['value']['createdAt'])
        rkey = record['uri'].split('/').last
        if created_at.to_date <= cutoff_date && !@exclude_ids.include?(rkey)
          old_likes << {
            uri: record['uri'],
            created_at: created_at
          }
        end
      end

      cursor = data['cursor']
      break unless cursor

      print "."
    end

    puts
    old_likes
  end

  def fetch_old_reposts
    cutoff_date = Date.today - @days_threshold
    old_reposts = []
    cursor = nil

    puts "🔍 Scanning for reposts older than #{cutoff_date}..."

    loop do
      uri = URI("#{API_BASE}/com.atproto.repo.listRecords")
      params = {
        repo: @did,
        collection: 'app.bsky.feed.repost',
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
        puts "❌ Failed to fetch reposts: #{response.body}"
        break
      end

      data = JSON.parse(response.body)

      data['records'].each do |record|
        created_at = DateTime.parse(record['value']['createdAt'])
        rkey = record['uri'].split('/').last
        if created_at.to_date <= cutoff_date && !@exclude_ids.include?(rkey)
          old_reposts << {
            uri: record['uri'],
            created_at: created_at
          }
        end
      end

      cursor = data['cursor']
      break unless cursor

      print "."
    end

    puts
    old_reposts
  end

  def delete_posts(posts)
    deleted_count = 0

    posts.each_with_index do |post, index|
      rkey = post[:uri].split('/').last
      if @dry_run
        puts "[DRY RUN] ID: #{rkey} | #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
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

  def delete_replies(replies)
    deleted_count = 0

    replies.each_with_index do |reply, index|
      rkey = reply[:uri].split('/').last
      if @dry_run
        puts "[DRY RUN] ID: #{rkey} | #{reply[:created_at].strftime('%Y-%m-%d')} - #{reply[:text]}"
      else
        if delete_post(reply[:uri])
          deleted_count += 1
          puts "🗑️  Deleted reply (#{index + 1}/#{replies.length}): #{reply[:created_at].strftime('%Y-%m-%d')} - #{reply[:text]}"
        else
          puts "❌ Failed to delete reply: #{reply[:created_at].strftime('%Y-%m-%d')} - #{reply[:text]}"
        end

        # Rate limiting - sleep briefly between deletions
        sleep(0.5)
      end
    end

    if @dry_run
      puts "🔍 DRY RUN: Would have deleted #{replies.length} replies"
    else
      puts "✅ Successfully deleted #{deleted_count} out of #{replies.length} replies"
    end
  end

  def delete_likes(likes)
    deleted_count = 0

    likes.each_with_index do |like, index|
      rkey = like[:uri].split('/').last
      if @dry_run
        puts "[DRY RUN] ID: #{rkey} | Like from #{like[:created_at].strftime('%Y-%m-%d')}"
      else
        if delete_like(like[:uri])
          deleted_count += 1
          puts "🗑️  Deleted like (#{index + 1}/#{likes.length}): #{like[:created_at].strftime('%Y-%m-%d')}"
        else
          puts "❌ Failed to delete like: #{like[:created_at].strftime('%Y-%m-%d')}"
        end

        # Rate limiting - sleep briefly between deletions
        sleep(0.5)
      end
    end

    if @dry_run
      puts "🔍 DRY RUN: Would have deleted #{likes.length} likes"
    else
      puts "✅ Successfully deleted #{deleted_count} out of #{likes.length} likes"
    end
  end

  def delete_reposts(reposts)
    deleted_count = 0

    reposts.each_with_index do |repost, index|
      rkey = repost[:uri].split('/').last
      if @dry_run
        puts "[DRY RUN] ID: #{rkey} | Repost from #{repost[:created_at].strftime('%Y-%m-%d')}"
      else
        if delete_repost(repost[:uri])
          deleted_count += 1
          puts "🗑️  Deleted repost (#{index + 1}/#{reposts.length}): #{repost[:created_at].strftime('%Y-%m-%d')}"
        else
          puts "❌ Failed to delete repost: #{repost[:created_at].strftime('%Y-%m-%d')}"
        end

        # Rate limiting - sleep briefly between deletions
        sleep(0.5)
      end
    end

    if @dry_run
      puts "🔍 DRY RUN: Would have deleted #{reposts.length} reposts"
    else
      puts "✅ Successfully deleted #{deleted_count} out of #{reposts.length} reposts"
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

  def delete_like(like_uri)
    # Extract the rkey from the URI
    rkey = like_uri.split('/').last

    uri = URI("#{API_BASE}/com.atproto.repo.deleteRecord")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      repo: @did,
      collection: 'app.bsky.feed.like',
      rkey: rkey
    }.to_json

    response = http.request(request)
    response.code == '200'
  end

  def delete_repost(repost_uri)
    # Extract the rkey from the URI
    rkey = repost_uri.split('/').last

    uri = URI("#{API_BASE}/com.atproto.repo.deleteRecord")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      repo: @did,
      collection: 'app.bsky.feed.repost',
      rkey: rkey
    }.to_json

    response = http.request(request)
    response.code == '200'
  end

  def fetch_specific_items(rkeys)
    posts = []
    replies = []
    reposts = []
    likes = []

    rkeys.each do |rkey|
      found = false

      # Skip if this ID is in the exclude list
      if @exclude_ids.include?(rkey)
        puts "🚫 Skipping excluded ID: #{rkey}"
        next
      end

      if (@delete_posts || @delete_replies)
        if item = fetch_record_by_rkey(rkey, 'app.bsky.feed.post')
          is_reply = item[:reply] != nil
          if @delete_posts && !is_reply
            posts << item
            found = true
          elsif @delete_replies && is_reply
            replies << item
            found = true
          end
        end
      end

      if @delete_reposts && !found
        if item = fetch_record_by_rkey(rkey, 'app.bsky.feed.repost')
          reposts << item
          found = true
        end
      end

      if @delete_likes && !found
        if item = fetch_record_by_rkey(rkey, 'app.bsky.feed.like')
          likes << item
          found = true
        end
      end

      unless found
        types_checked = []
        types_checked << 'posts' if @delete_posts
        types_checked << 'replies' if @delete_replies
        types_checked << 'reposts' if @delete_reposts
        types_checked << 'likes' if @delete_likes
        puts "⚠️  ID '#{rkey}' not found in #{types_checked.join(', ')} collections"
      end
    end

    [posts, replies, reposts, likes]
  end

  def fetch_record_by_rkey(rkey, collection)
    uri = URI("#{API_BASE}/com.atproto.repo.getRecord")
    params = {
      repo: @did,
      collection: collection,
      rkey: rkey
    }
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      created_at = DateTime.parse(data['value']['createdAt'])
      
      result = {
        uri: data['uri'],
        created_at: created_at
      }

      # Add text for posts and capture reply field
      if collection == 'app.bsky.feed.post'
        result[:text] = data['value']['text']&.slice(0, 100)
        result[:reply] = data['value']['reply']
      end

      result
    else
      nil
    end
  rescue => e
    nil
  end

  def show_usage
    puts "Usage: #{$0} [posts|replies|likes|reposts] [options]"
    puts ""
    puts "Commands:"
    puts "  posts     Delete posts (not replies)"
    puts "  replies   Delete replies"
    puts "  likes     Delete likes"
    puts "  reposts   Delete reposts"
    puts "  (You can specify multiple commands)"
    puts ""
    puts "Options:"
    puts "  -d, --days DAYS                  Delete content older than DAYS (default: 90)"
    puts "  -n, --dry-run                    Show what would be deleted without actually deleting (default)"
    puts "  -f, --force                      Actually delete content (required to disable dry-run mode)"
    puts "      --ids ID1,ID2,ID3            Delete only specific IDs of the specified type (comma-separated rkeys)"
    puts "      --exclude-ids ID1,ID2,ID3    Exclude specific IDs from deletion (comma-separated rkeys)"
    puts "  -h, --help                       Show this help message"
    puts "  -v, --version                    Show version"
    puts ""
    puts "Examples:"
    puts "  #{$0} posts likes -n             # Show old posts and likes (dry run)"
    puts "  #{$0} replies --days 30 -f       # Delete replies older than 30 days"
    puts "  #{$0} likes --ids abc123,def456  # Delete only specific like IDs"
  end
end

# Only run if this file is executed directly
if __FILE__ == $0
  VanillaSky.new.run(ARGV)
end
