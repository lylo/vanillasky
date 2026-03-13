require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'openssl'

class MastodonPlatform
  def initialize
    @access_token = nil
    @account_id = nil
    @instance = nil
  end

  def platform_name
    'Mastodon'
  end

  def authenticate
    @instance = ENV['MASTODON_INSTANCE']
    @access_token = ENV['MASTODON_ACCESS_TOKEN']

    if @instance.nil? || @instance.empty?
      print "Enter your Mastodon instance (e.g., mastodon.social): "
      @instance = STDIN.gets.chomp
    end

    if @access_token.nil? || @access_token.empty?
      print "Enter your access token: "
      @access_token = STDIN.gets.chomp
    end

    @instance = @instance.gsub(%r{^https?://}, '').chomp('/')

    uri = URI("https://#{@instance}/api/v1/accounts/verify_credentials")
    http = create_http(uri)

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      @account_id = data['id']
      username = data['acct'] || data['username']
      puts "✅ Successfully authenticated as #{username}@#{@instance}"
    else
      puts "❌ Authentication failed: #{response.body}"
      exit 1
    end
  end

  def fetch_old_posts(cutoff_date, start_date, exclude_ids)
    old_posts = []

    puts "🔍 Scanning for posts older than #{cutoff_date}..."

    paginate("/api/v1/accounts/#{@account_id}/statuses", exclude_replies: true, exclude_reblogs: true) do |status|
      created_at = DateTime.parse(status['created_at'])

      break :stop if created_at.to_date <= cutoff_date && start_date && created_at.to_date < start_date

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(status['id']) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_posts << {
          uri: status['id'],
          created_at: created_at,
          text: (status['content'] || '').gsub(/<[^>]*>/, '').slice(0, 100)
        }
      end
    end

    puts
    old_posts
  end

  def fetch_old_replies(cutoff_date, start_date, exclude_ids)
    old_replies = []

    puts "🔍 Scanning for replies older than #{cutoff_date}..."

    paginate("/api/v1/accounts/#{@account_id}/statuses", exclude_reblogs: true) do |status|
      created_at = DateTime.parse(status['created_at'])
      is_reply = !status['in_reply_to_id'].nil?

      next unless is_reply

      break :stop if created_at.to_date <= cutoff_date && start_date && created_at.to_date < start_date

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(status['id']) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_replies << {
          uri: status['id'],
          created_at: created_at,
          text: (status['content'] || '').gsub(/<[^>]*>/, '').slice(0, 100)
        }
      end
    end

    puts
    old_replies
  end

  def fetch_old_likes(cutoff_date, start_date, exclude_ids)
    old_likes = []

    puts "🔍 Scanning for favourites older than #{cutoff_date}..."

    paginate("/api/v1/favourites") do |status|
      created_at = DateTime.parse(status['created_at'])

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(status['id']) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_likes << {
          uri: status['id'],
          created_at: created_at
        }
      end
    end

    puts
    old_likes
  end

  def fetch_old_reposts(cutoff_date, start_date, exclude_ids)
    old_reposts = []

    puts "🔍 Scanning for boosts older than #{cutoff_date}..."

    paginate("/api/v1/accounts/#{@account_id}/statuses") do |status|
      next unless status['reblog']

      created_at = DateTime.parse(status['created_at'])

      break :stop if created_at.to_date <= cutoff_date && start_date && created_at.to_date < start_date

      if created_at.to_date <= cutoff_date && !exclude_ids.include?(status['id']) &&
         (start_date.nil? || created_at.to_date >= start_date)
        old_reposts << {
          uri: status['id'],
          created_at: created_at
        }
      end
    end

    puts
    old_reposts
  end

  def fetch_record_by_id(id, collection)
    uri = URI("https://#{@instance}/api/v1/statuses/#{id}")
    http = create_http(uri)

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"

    response = http.request(request)

    if response.code == '200'
      status = JSON.parse(response.body)
      created_at = DateTime.parse(status['created_at'])

      result = {
        uri: status['id'],
        created_at: created_at
      }

      if status['reblog']
        result[:reply] = nil
      elsif status['in_reply_to_id']
        result[:reply] = status['in_reply_to_id']
        result[:text] = (status['content'] || '').gsub(/<[^>]*>/, '').slice(0, 100)
      else
        result[:text] = (status['content'] || '').gsub(/<[^>]*>/, '').slice(0, 100)
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
    when :post, :reply then 'status'
    when :repost then 'reblog'
    when :like then 'favourite'
    end
  end

  def delete_post(status_id)
    request_with_retry(:delete, "/api/v1/statuses/#{status_id}")
  end

  def delete_like(status_id)
    request_with_retry(:post, "/api/v1/statuses/#{status_id}/unfavourite")
  end

  def delete_repost(status_id)
    request_with_retry(:post, "/api/v1/statuses/#{status_id}/unreblog")
  end

  def delete_delay
    1.0
  end

  def item_id(item)
    item[:uri]
  end

  private

  def request_with_retry(method, path, retries: 3)
    retries.times do |attempt|
      uri = URI("https://#{@instance}#{path}")
      http = create_http(uri)

      request = case method
                when :delete then Net::HTTP::Delete.new(uri)
                when :post then Net::HTTP::Post.new(uri)
                end
      request['Authorization'] = "Bearer #{@access_token}"

      response = http.request(request)

      if response.code == '429'
        wait = (response['Retry-After'] || 30).to_i
        puts "⏳ Rate limited, waiting #{wait}s..."
        sleep(wait)
        next
      end

      return response.code == '200'
    end

    false
  end

  def paginate(path, params = {})
    url = "https://#{@instance}#{path}"
    query_params = params.map { |k, v| "#{k}=#{v}" }.join('&')
    url += "?#{query_params}" unless query_params.empty?

    loop do
      uri = URI(url)
      http = create_http(uri)

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"

      response = http.request(request)

      if response.code != '200'
        puts "❌ Failed to fetch data: #{response.body}"
        break
      end

      statuses = JSON.parse(response.body)
      break if statuses.empty?

      stop = false
      statuses.each do |status|
        result = yield status
        if result == :stop
          stop = true
          break
        end
      end

      break if stop

      # Parse Link header for next page
      link_header = response['Link']
      break unless link_header

      next_link = link_header.split(',').find { |l| l.include?('rel="next"') }
      break unless next_link

      url = next_link.match(/<([^>]+)>/)[1]

      print "."
    end
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
