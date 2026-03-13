require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'openssl'

class BlueskyPlatform
  API_BASE = 'https://bsky.social/xrpc'

  def initialize
    @access_token = nil
    @did = nil
  end

  def platform_name
    'Bluesky'
  end

  def authenticate
    handle = ENV['BLUESKY_HANDLE']
    password = ENV['BLUESKY_APP_PASSWORD']

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
    http = create_http(uri)

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

  def fetch_old_posts(cutoff_date, start_date, exclude_ids)
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
      http = create_http(uri)

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

        if created_at.to_date <= cutoff_date && !exclude_ids.include?(rkey) &&
           (start_date.nil? || created_at.to_date >= start_date) && !is_reply
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

  def fetch_old_replies(cutoff_date, start_date, exclude_ids)
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
      http = create_http(uri)

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

        if created_at.to_date <= cutoff_date && !exclude_ids.include?(rkey) &&
           (start_date.nil? || created_at.to_date >= start_date) && is_reply
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

  def fetch_old_likes(cutoff_date, start_date, exclude_ids)
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
      http = create_http(uri)

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
        if created_at.to_date <= cutoff_date && !exclude_ids.include?(rkey) &&
           (start_date.nil? || created_at.to_date >= start_date)
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

  def fetch_old_reposts(cutoff_date, start_date, exclude_ids)
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
      http = create_http(uri)

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
        if created_at.to_date <= cutoff_date && !exclude_ids.include?(rkey) &&
           (start_date.nil? || created_at.to_date >= start_date)
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

  def fetch_record_by_id(rkey, collection)
    uri = URI("#{API_BASE}/com.atproto.repo.getRecord")
    params = {
      repo: @did,
      collection: collection,
      rkey: rkey
    }
    uri.query = URI.encode_www_form(params)

    http = create_http(uri)

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

  def collection_for_type(type)
    case type
    when :post, :reply then 'app.bsky.feed.post'
    when :repost then 'app.bsky.feed.repost'
    when :like then 'app.bsky.feed.like'
    end
  end

  def delete_post(post_uri)
    rkey = post_uri.split('/').last
    delete_record('app.bsky.feed.post', rkey)
  end

  def delete_like(like_uri)
    rkey = like_uri.split('/').last
    delete_record('app.bsky.feed.like', rkey)
  end

  def delete_repost(repost_uri)
    rkey = repost_uri.split('/').last
    delete_record('app.bsky.feed.repost', rkey)
  end

  def delete_delay
    0.5
  end

  def item_id(item)
    item[:uri].split('/').last
  end

  private

  def delete_record(collection, rkey)
    uri = URI("#{API_BASE}/com.atproto.repo.deleteRecord")
    http = create_http(uri)

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    request['Content-Type'] = 'application/json'
    request.body = {
      repo: @did,
      collection: collection,
      rkey: rkey
    }.to_json

    response = http.request(request)
    response.code == '200'
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
