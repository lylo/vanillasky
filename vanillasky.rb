#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'optparse'
require 'dotenv/load'
require 'openssl'

require_relative 'bluesky_platform'
require_relative 'mastodon_platform'

class VanillaSky
  VERSION = '0.3.0'

  def initialize
    @platform = nil
    @platform_name = 'bluesky'
    @days_threshold = 90
    @dry_run = true
    @delete_reposts = false
    @delete_likes = false
    @delete_posts = false
    @delete_replies = false
    @specific_ids = []
    @exclude_ids = []
    @start_date = nil
  end

  def run(args)
    parse_command_and_options(args)

    @platform = create_platform

    puts "🌌 VanillaSky - #{@platform.platform_name} Auto-Delete"
    puts "========================================="

    @platform.authenticate

    if @dry_run
      puts "🔍 DRY RUN MODE - Nothing will be deleted"
    end

    if @exclude_ids.any?
      puts "🚫 Excluding #{@exclude_ids.length} IDs from deletion: #{@exclude_ids.join(', ')}"
    end

    if @start_date
      puts "📅 Not deleting anything before #{@start_date.strftime('%Y-%m-%d')}"
    end

    cutoff_date = Date.today - @days_threshold

    if @specific_ids.any?
      posts, replies, reposts, likes = fetch_specific_items(@specific_ids)
    else
      posts = @delete_posts ? @platform.fetch_old_posts(cutoff_date, @start_date, @exclude_ids) : []
      replies = @delete_replies ? @platform.fetch_old_replies(cutoff_date, @start_date, @exclude_ids) : []
      reposts = @delete_reposts ? @platform.fetch_old_reposts(cutoff_date, @start_date, @exclude_ids) : []
      likes = @delete_likes ? @platform.fetch_old_likes(cutoff_date, @start_date, @exclude_ids) : []
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

  def create_platform
    case @platform_name
    when 'bluesky'
      BlueskyPlatform.new
    when 'mastodon'
      MastodonPlatform.new
    else
      puts "❌ Error: Unknown platform '#{@platform_name}'"
      puts "   Valid platforms: bluesky, mastodon"
      exit 1
    end
  end

  def parse_command_and_options(args)
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
      opts.banner = "Usage: #{$0} [posts|replies|likes|reposts] [options]"

      opts.on("-p", "--platform PLATFORM", "Platform to use: bluesky (default), mastodon") do |platform|
        @platform_name = platform.downcase
      end

      opts.on("-d", "--days DAYS", Integer, "Delete content older than DAYS (default: 90)") do |days|
        @days_threshold = days
      end

      opts.on("-s", "--start-date DATE", "Don't delete anything before this date (YYYY-MM-DD)") do |date|
        begin
          @start_date = Date.parse(date)
        rescue Date::Error
          puts "❌ Error: Invalid date format. Use YYYY-MM-DD (e.g., 2024-01-01)"
          exit 1
        end
      end

      opts.on("-n", "--dry-run", "Show what would be deleted without actually deleting (default)") do
        @dry_run = true
      end

      opts.on("-f", "--force", "Actually delete content (required to disable dry-run mode)") do
        @dry_run = false
      end

      opts.on("--ids ID1,ID2,ID3", Array, "Delete only specific IDs of the specified type (comma-separated)") do |ids|
        @specific_ids = ids.map(&:strip)
      end

      opts.on("--exclude-ids ID1,ID2,ID3", Array, "Exclude specific IDs from deletion (comma-separated)") do |ids|
        @exclude_ids = ids.map(&:strip)
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

  def fetch_specific_items(ids)
    posts = []
    replies = []
    reposts = []
    likes = []

    ids.each do |id|
      found = false

      if @exclude_ids.include?(id)
        puts "🚫 Skipping excluded ID: #{id}"
        next
      end

      if (@delete_posts || @delete_replies)
        collection = @platform.collection_for_type(:post)
        if item = @platform.fetch_record_by_id(id, collection)
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
        collection = @platform.collection_for_type(:repost)
        if item = @platform.fetch_record_by_id(id, collection)
          reposts << item
          found = true
        end
      end

      if @delete_likes && !found
        collection = @platform.collection_for_type(:like)
        if item = @platform.fetch_record_by_id(id, collection)
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
        puts "⚠️  ID '#{id}' not found in #{types_checked.join(', ')} collections"
      end
    end

    [posts, replies, reposts, likes]
  end

  def delete_posts(posts)
    deleted_count = 0

    posts.each_with_index do |post, index|
      id = @platform.item_id(post)
      if @dry_run
        puts "[DRY RUN] ID: #{id} | #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
      else
        if @platform.delete_post(post[:uri])
          deleted_count += 1
          puts "🗑️  Deleted (#{index + 1}/#{posts.length}): #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
        else
          puts "❌ Failed to delete: #{post[:created_at].strftime('%Y-%m-%d')} - #{post[:text]}"
        end

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
      id = @platform.item_id(reply)
      if @dry_run
        puts "[DRY RUN] ID: #{id} | #{reply[:created_at].strftime('%Y-%m-%d')} - #{reply[:text]}"
      else
        if @platform.delete_post(reply[:uri])
          deleted_count += 1
          puts "🗑️  Deleted reply (#{index + 1}/#{replies.length}): #{reply[:created_at].strftime('%Y-%m-%d')} - #{reply[:text]}"
        else
          puts "❌ Failed to delete reply: #{reply[:created_at].strftime('%Y-%m-%d')} - #{reply[:text]}"
        end

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
      id = @platform.item_id(like)
      if @dry_run
        puts "[DRY RUN] ID: #{id} | Like from #{like[:created_at].strftime('%Y-%m-%d')}"
      else
        if @platform.delete_like(like[:uri])
          deleted_count += 1
          puts "🗑️  Deleted like (#{index + 1}/#{likes.length}): #{like[:created_at].strftime('%Y-%m-%d')}"
        else
          puts "❌ Failed to delete like: #{like[:created_at].strftime('%Y-%m-%d')}"
        end

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
      id = @platform.item_id(repost)
      if @dry_run
        puts "[DRY RUN] ID: #{id} | Repost from #{repost[:created_at].strftime('%Y-%m-%d')}"
      else
        if @platform.delete_repost(repost[:uri])
          deleted_count += 1
          puts "🗑️  Deleted repost (#{index + 1}/#{reposts.length}): #{repost[:created_at].strftime('%Y-%m-%d')}"
        else
          puts "❌ Failed to delete repost: #{repost[:created_at].strftime('%Y-%m-%d')}"
        end

        sleep(0.5)
      end
    end

    if @dry_run
      puts "🔍 DRY RUN: Would have deleted #{reposts.length} reposts"
    else
      puts "✅ Successfully deleted #{deleted_count} out of #{reposts.length} reposts"
    end
  end

  def show_usage
    puts "Usage: #{$0} [posts|replies|likes|reposts] [options]"
    puts ""
    puts "Commands:"
    puts "  posts     Delete posts (not replies)"
    puts "  replies   Delete replies"
    puts "  likes     Delete likes / favourites"
    puts "  reposts   Delete reposts / boosts"
    puts "  (You can specify multiple commands)"
    puts ""
    puts "Options:"
    puts "  -p, --platform PLATFORM          Platform to use: bluesky (default), mastodon"
    puts "  -d, --days DAYS                  Delete content older than DAYS (default: 90)"
    puts "  -s, --start-date DATE            Don't delete anything before this date (YYYY-MM-DD)"
    puts "  -n, --dry-run                    Show what would be deleted without actually deleting (default)"
    puts "  -f, --force                      Actually delete content (required to disable dry-run mode)"
    puts "      --ids ID1,ID2,ID3            Delete only specific IDs of the specified type (comma-separated)"
    puts "      --exclude-ids ID1,ID2,ID3    Exclude specific IDs from deletion (comma-separated)"
    puts "  -h, --help                       Show this help message"
    puts "  -v, --version                    Show version"
    puts ""
    puts "Examples:"
    puts "  #{$0} posts likes -n                                    # Show old posts and likes (dry run)"
    puts "  #{$0} replies --days 30 -f                              # Delete replies older than 30 days"
    puts "  #{$0} posts --start-date 2024-01-01 -f                  # Delete posts but keep everything since 2024"
    puts "  #{$0} likes --ids abc123,def456                         # Delete only specific like IDs"
    puts "  #{$0} posts -p mastodon -n                              # Show old Mastodon posts (dry run)"
    puts ""
    puts "Environment variables:"
    puts "  Bluesky:  BLUESKY_HANDLE, BLUESKY_APP_PASSWORD"
    puts "  Mastodon: MASTODON_INSTANCE, MASTODON_ACCESS_TOKEN"
  end
end

# Only run if this file is executed directly
if __FILE__ == $0
  VanillaSky.new.run(ARGV)
end
