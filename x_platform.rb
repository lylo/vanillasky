require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'openssl'
require 'base64'
require 'securerandom'
require 'tmpdir'

class XPlatform
  API_BASE = 'https://api.twitter.com'
  TWITTER_EPOCH = 1288834974657 # Twitter snowflake epoch in milliseconds

  def initialize(archive_path)
    @archive_path = archive_path
    @consumer_key = nil
    @consumer_secret = nil
    @access_token = nil
    @access_token_secret = nil
    @user_id = nil
    @tweets_cache = nil
    @likes_cache = nil
  end

  def platform_name
    'X (Twitter)'
  end

  def authenticate
    @consumer_key = ENV['X_API_KEY']
    @consumer_secret = ENV['X_API_KEY_SECRET']
    @access_token = ENV['X_ACCESS_TOKEN']
    @access_token_secret = ENV['X_ACCESS_TOKEN_SECRET']

    if @consumer_key.nil? || @consumer_key.empty?
      print "Enter your X API Key (Consumer Key): "
      @consumer_key = STDIN.gets.chomp
    end

    if @consumer_secret.nil? || @consumer_secret.empty?
      print "Enter your X API Key Secret (Consumer Secret): "
      @consumer_secret = STDIN.gets.chomp
    end

    if @access_token.nil? || @access_token.empty?
      print "Enter your X Access Token: "
      @access_token = STDIN.gets.chomp
    end

    if @access_token_secret.nil? || @access_token_secret.empty?
      print "Enter your X Access Token Secret: "
      @access_token_secret = STDIN.gets.chomp
    end

    validate_archive_path
    load_account_info

    puts "✅ Loaded account: @#{@username} (#{@user_id})"
    puts "📂 Using archive: #{@archive_path}"
  end

  def fetch_old_posts(cutoff_date, start_date, exclude_ids)
    old_posts = []
    tweets = load_tweets

    puts "🔍 Scanning archive for posts older than #{cutoff_date}..."

    tweets.each do |tweet|
      created_at = parse_tweet_date(tweet['created_at'])
      id = tweet['id_str'] || tweet['id'].to_s
      is_reply = !tweet['in_reply_to_status_id_str'].nil? && !tweet['in_reply_to_status_id_str'].empty?
      is_retweet = tweet['full_text']&.start_with?('RT @')

      next if is_reply || is_retweet

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(id) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_posts << {
          uri: id,
          created_at: created_at,
          text: (tweet['full_text'] || '').slice(0, 100)
        }
      end
    end

    old_posts
  end

  def fetch_old_replies(cutoff_date, start_date, exclude_ids)
    old_replies = []
    tweets = load_tweets

    puts "🔍 Scanning archive for replies older than #{cutoff_date}..."

    tweets.each do |tweet|
      created_at = parse_tweet_date(tweet['created_at'])
      id = tweet['id_str'] || tweet['id'].to_s
      is_reply = !tweet['in_reply_to_status_id_str'].nil? && !tweet['in_reply_to_status_id_str'].empty?

      next unless is_reply

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(id) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_replies << {
          uri: id,
          created_at: created_at,
          text: (tweet['full_text'] || '').slice(0, 100)
        }
      end
    end

    old_replies
  end

  def fetch_old_reposts(cutoff_date, start_date, exclude_ids)
    old_reposts = []
    tweets = load_tweets

    puts "🔍 Scanning archive for retweets older than #{cutoff_date}..."

    tweets.each do |tweet|
      created_at = parse_tweet_date(tweet['created_at'])
      id = tweet['id_str'] || tweet['id'].to_s
      is_retweet = tweet['full_text']&.start_with?('RT @')

      next unless is_retweet

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(id) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_reposts << {
          uri: id,
          created_at: created_at
        }
      end
    end

    old_reposts
  end

  def fetch_old_likes(cutoff_date, start_date, exclude_ids)
    old_likes = []
    likes = load_likes

    puts "🔍 Scanning archive for likes older than #{cutoff_date}..."

    likes.each do |like|
      tweet_id = like['tweetId']
      next if exclude_ids.include?(tweet_id)

      created_at = date_from_snowflake(tweet_id)

      if created_at.to_date <= cutoff_date &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_likes << {
          uri: tweet_id,
          created_at: created_at
        }
      end
    end

    old_likes
  end

  def fetch_record_by_id(id, collection)
    case collection
    when 'tweet'
      tweets = load_tweets
      tweet = tweets.find { |t| (t['id_str'] || t['id'].to_s) == id }
      return nil unless tweet

      created_at = parse_tweet_date(tweet['created_at'])
      is_reply = !tweet['in_reply_to_status_id_str'].nil? && !tweet['in_reply_to_status_id_str'].empty?

      result = {
        uri: id,
        created_at: created_at,
        text: (tweet['full_text'] || '').slice(0, 100)
      }
      result[:reply] = tweet['in_reply_to_status_id_str'] if is_reply
      result
    when 'like'
      likes = load_likes
      like = likes.find { |l| l['tweetId'] == id }
      return nil unless like

      {
        uri: like['tweetId'],
        created_at: date_from_snowflake(like['tweetId'])
      }
    else
      nil
    end
  rescue => e
    nil
  end

  def collection_for_type(type)
    case type
    when :post, :reply, :repost then 'tweet'
    when :like then 'like'
    end
  end

  def delete_post(tweet_id)
    url = "#{API_BASE}/1.1/statuses/destroy/#{tweet_id}.json"
    oauth_request(:post, url)
  end

  def delete_like(tweet_id)
    url = "#{API_BASE}/1.1/favorites/destroy.json"
    oauth_request(:post, url, params: { 'id' => tweet_id })
  end

  def delete_repost(tweet_id)
    url = "#{API_BASE}/1.1/statuses/destroy/#{tweet_id}.json"
    oauth_request(:post, url)
  end

  def delete_delay
    1.0
  end

  def item_id(item)
    item[:uri]
  end

  private

  def validate_archive_path
    unless @archive_path
      puts "❌ Error: X platform requires an archive path (--archive)"
      puts "   Request your archive at: https://x.com/settings/download_your_data"
      exit 1
    end

    @archive_path = File.expand_path(@archive_path)

    if File.file?(@archive_path) && @archive_path.end_with?('.zip')
      extract_dir = Dir.mktmpdir('vanillasky-archive-')
      puts "📦 Extracting archive to #{extract_dir}..."
      system('unzip', '-q', @archive_path, '-d', extract_dir)

      # The zip may contain a top-level directory or files directly
      entries = Dir.children(extract_dir)
      if entries.length == 1 && File.directory?(File.join(extract_dir, entries.first))
        @archive_path = File.join(extract_dir, entries.first)
      else
        @archive_path = extract_dir
      end
    end

    unless File.directory?(@archive_path)
      puts "❌ Error: Archive path not found: #{@archive_path}"
      exit 1
    end

    data_dir = File.join(@archive_path, 'data')
    unless File.directory?(data_dir)
      puts "❌ Error: No 'data' directory found in archive: #{@archive_path}"
      puts "   Expected extracted archive with data/tweets.js, data/like.js, etc."
      exit 1
    end
  end

  def load_account_info
    file = find_archive_file('account.js')
    unless file
      puts "❌ Error: No account.js found in archive"
      exit 1
    end

    raw = File.read(file)
    json = raw.sub(/\Awindow\.YTD\.\w+\.part0\s*=\s*/, '')
    data = JSON.parse(json)

    account = data.first['account']
    @user_id = account['accountId']
    @username = account['username']
  end

  def load_tweets
    return @tweets_cache if @tweets_cache

    file = find_archive_file('tweets.js', 'tweet.js')
    unless file
      puts "⚠️  No tweets file found in archive"
      @tweets_cache = []
      return @tweets_cache
    end

    raw = File.read(file)
    json = raw.sub(/\Awindow\.YTD\.\w+\.part0\s*=\s*/, '')
    data = JSON.parse(json)

    @tweets_cache = data.map { |entry| entry['tweet'] || entry }
    puts "📂 Loaded #{@tweets_cache.length} tweets from archive"
    @tweets_cache
  end

  def load_likes
    return @likes_cache if @likes_cache

    file = find_archive_file('like.js', 'likes.js')
    unless file
      puts "⚠️  No likes file found in archive"
      @likes_cache = []
      return @likes_cache
    end

    raw = File.read(file)
    json = raw.sub(/\Awindow\.YTD\.\w+\.part0\s*=\s*/, '')
    data = JSON.parse(json)

    @likes_cache = data.map { |entry| entry['like'] || entry }
    puts "📂 Loaded #{@likes_cache.length} likes from archive"
    @likes_cache
  end

  def find_archive_file(*names)
    names.each do |name|
      path = File.join(@archive_path, 'data', name)
      return path if File.exist?(path)
    end
    nil
  end

  def parse_tweet_date(date_str)
    DateTime.strptime(date_str, '%a %b %d %H:%M:%S %z %Y')
  rescue
    DateTime.parse(date_str)
  end

  def date_from_snowflake(id_str)
    id = id_str.to_i
    timestamp_ms = (id >> 22) + TWITTER_EPOCH
    Time.at(timestamp_ms / 1000.0).to_datetime
  end

  def oauth_request(method, url, retries: 3, params: {})
    retries.times do |attempt|
      request_url = url
      if params.any?
        request_url = "#{url}?#{URI.encode_www_form(params)}"
      end
      uri = URI(request_url)
      http = create_http(uri)

      request = case method
                when :delete then Net::HTTP::Delete.new(uri)
                when :post then Net::HTTP::Post.new(uri)
                end
      request['Authorization'] = oauth_header(method.to_s.upcase, url, params)

      response = http.request(request)

      if response.code == '429'
        wait = (response['Retry-After'] || 30).to_i
        puts "⏳ Rate limited, waiting #{wait}s..."
        sleep(wait)
        next
      end

      if response.code == '404'
        return true # already deleted
      end

      unless response.code == '200'
        puts "   ⚠️  API #{response.code}: #{response.body[0..200]}"
      end

      return response.code == '200'
    end

    false
  end

  def oauth_header(method, url, params = {})
    oauth_params = {
      'oauth_consumer_key' => @consumer_key,
      'oauth_nonce' => SecureRandom.hex(16),
      'oauth_signature_method' => 'HMAC-SHA1',
      'oauth_timestamp' => Time.now.to_i.to_s,
      'oauth_token' => @access_token,
      'oauth_version' => '1.0'
    }

    all_params = oauth_params.merge(params)
    sorted = all_params.sort.map { |k, v| "#{percent_encode(k)}=#{percent_encode(v)}" }.join('&')

    base_url = url.split('?').first
    base_string = [method.upcase, percent_encode(base_url), percent_encode(sorted)].join('&')
    signing_key = "#{percent_encode(@consumer_secret)}&#{percent_encode(@access_token_secret)}"

    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('SHA1', signing_key, base_string)
    )

    oauth_params['oauth_signature'] = signature

    'OAuth ' + oauth_params.sort.map { |k, v| "#{percent_encode(k)}=\"#{percent_encode(v)}\"" }.join(', ')
  end

  def percent_encode(str)
    URI.encode_www_form_component(str.to_s).gsub('+', '%20')
  end

  def create_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = OpenSSL::X509::Store.new.tap do |store|
      store.set_default_paths
      store.flags = OpenSSL::X509::V_FLAG_NO_CHECK_TIME
    end
    http
  end
end
