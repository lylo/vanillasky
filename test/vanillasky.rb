require 'minitest/autorun'
require 'date'
require 'tmpdir'
require 'fileutils'
require_relative '../vanillasky'

class VanillaSkyTest < Minitest::Test
  def setup
    @vs = VanillaSky.new
  end

  def test_initialize_defaults
    assert_nil @vs.instance_variable_get(:@platform)
    assert_equal 'bluesky', @vs.instance_variable_get(:@platform_name)
    assert_equal 90, @vs.instance_variable_get(:@days_threshold)
    assert_equal true, @vs.instance_variable_get(:@dry_run)
    assert_equal false, @vs.instance_variable_get(:@delete_reposts)
    assert_equal false, @vs.instance_variable_get(:@delete_likes)
    assert_equal false, @vs.instance_variable_get(:@delete_posts)
    assert_equal false, @vs.instance_variable_get(:@delete_replies)
  end

  def test_parse_options_days
    @vs.send(:parse_options, ['-d', '30'])
    assert_equal 30, @vs.instance_variable_get(:@days_threshold)
  end

  def test_parse_options_dry_run
    @vs.send(:parse_options, ['-n'])
    assert_equal true, @vs.instance_variable_get(:@dry_run)
  end

  def test_parse_options_force
    @vs.send(:parse_options, ['-f'])
    assert_equal false, @vs.instance_variable_get(:@dry_run)
  end

  def test_parse_options_platform_bluesky
    @vs.send(:parse_options, ['-p', 'bluesky'])
    assert_equal 'bluesky', @vs.instance_variable_get(:@platform_name)
  end

  def test_parse_options_platform_mastodon
    @vs.send(:parse_options, ['-p', 'mastodon'])
    assert_equal 'mastodon', @vs.instance_variable_get(:@platform_name)
  end

  def test_parse_options_platform_case_insensitive
    @vs.send(:parse_options, ['-p', 'Mastodon'])
    assert_equal 'mastodon', @vs.instance_variable_get(:@platform_name)
  end

  def test_parse_options_help
    assert_raises(SystemExit) do
      capture_io do
        @vs.send(:parse_options, ['-h'])
      end
    end
  end

  def test_parse_command_posts
    @vs.send(:parse_command_and_options, ['posts', '-n'])
    assert_equal true, @vs.instance_variable_get(:@delete_posts)
    assert_equal false, @vs.instance_variable_get(:@delete_replies)
    assert_equal false, @vs.instance_variable_get(:@delete_likes)
    assert_equal false, @vs.instance_variable_get(:@delete_reposts)
  end

  def test_parse_command_multiple
    @vs.send(:parse_command_and_options, ['posts', 'likes', 'reposts', '-n'])
    assert_equal true, @vs.instance_variable_get(:@delete_posts)
    assert_equal false, @vs.instance_variable_get(:@delete_replies)
    assert_equal true, @vs.instance_variable_get(:@delete_likes)
    assert_equal true, @vs.instance_variable_get(:@delete_reposts)
  end

  def test_parse_command_with_platform
    @vs.send(:parse_command_and_options, ['posts', '-p', 'mastodon', '-n'])
    assert_equal true, @vs.instance_variable_get(:@delete_posts)
    assert_equal 'mastodon', @vs.instance_variable_get(:@platform_name)
  end

  def test_create_platform_bluesky
    @vs.instance_variable_set(:@platform_name, 'bluesky')
    platform = @vs.send(:create_platform)
    assert_instance_of BlueskyPlatform, platform
    assert_equal 'Bluesky', platform.platform_name
  end

  def test_create_platform_mastodon
    @vs.instance_variable_set(:@platform_name, 'mastodon')
    platform = @vs.send(:create_platform)
    assert_instance_of MastodonPlatform, platform
    assert_equal 'Mastodon', platform.platform_name
  end

  def test_create_platform_x
    @vs.instance_variable_set(:@platform_name, 'x')
    @vs.instance_variable_set(:@archive_path, '/tmp/fake-archive')
    platform = @vs.send(:create_platform)
    assert_instance_of XPlatform, platform
    assert_equal 'X (Twitter)', platform.platform_name
  end

  def test_create_platform_unknown
    @vs.instance_variable_set(:@platform_name, 'twitter')
    assert_raises(SystemExit) do
      capture_io do
        @vs.send(:create_platform)
      end
    end
  end

  def test_version
    assert_equal '0.4.0', VanillaSky::VERSION
  end

  def test_bluesky_item_id
    platform = BlueskyPlatform.new
    item = { uri: 'at://did:example:123/app.bsky.feed.post/abc123', created_at: DateTime.now }
    assert_equal 'abc123', platform.item_id(item)
  end

  def test_mastodon_item_id
    platform = MastodonPlatform.new
    item = { uri: '123456789', created_at: DateTime.now }
    assert_equal '123456789', platform.item_id(item)
  end

  def test_bluesky_collection_for_type
    platform = BlueskyPlatform.new
    assert_equal 'app.bsky.feed.post', platform.collection_for_type(:post)
    assert_equal 'app.bsky.feed.post', platform.collection_for_type(:reply)
    assert_equal 'app.bsky.feed.repost', platform.collection_for_type(:repost)
    assert_equal 'app.bsky.feed.like', platform.collection_for_type(:like)
  end

  def test_mastodon_collection_for_type
    platform = MastodonPlatform.new
    assert_equal 'status', platform.collection_for_type(:post)
    assert_equal 'status', platform.collection_for_type(:reply)
    assert_equal 'reblog', platform.collection_for_type(:repost)
    assert_equal 'favourite', platform.collection_for_type(:like)
  end

  def test_x_item_id
    platform = XPlatform.new('/tmp')
    item = { uri: '1234567890', created_at: DateTime.now }
    assert_equal '1234567890', platform.item_id(item)
  end

  def test_x_collection_for_type
    platform = XPlatform.new('/tmp')
    assert_equal 'tweet', platform.collection_for_type(:post)
    assert_equal 'tweet', platform.collection_for_type(:reply)
    assert_equal 'tweet', platform.collection_for_type(:repost)
    assert_equal 'like', platform.collection_for_type(:like)
  end

  def test_parse_options_start_date
    @vs.send(:parse_options, ['-s', '2024-06-01'])
    assert_equal Date.new(2024, 6, 1), @vs.instance_variable_get(:@start_date)
  end

  def test_parse_options_invalid_start_date
    assert_raises(SystemExit) do
      capture_io do
        @vs.send(:parse_options, ['-s', 'not-a-date'])
      end
    end
  end

  def test_parse_options_specific_ids
    @vs.send(:parse_options, ['--ids', 'abc,def,ghi'])
    assert_equal ['abc', 'def', 'ghi'], @vs.instance_variable_get(:@specific_ids)
  end

  def test_parse_options_archive_path
    @vs.send(:parse_options, ['--archive', '/tmp/my-archive'])
    assert_equal '/tmp/my-archive', @vs.instance_variable_get(:@archive_path)
  end

  def test_parse_options_exclude_ids
    @vs.send(:parse_options, ['--exclude-ids', 'abc,def'])
    assert_equal ['abc', 'def'], @vs.instance_variable_get(:@exclude_ids)
  end

  def test_parse_options_ids_and_exclude_ids_mutually_exclusive
    assert_raises(SystemExit) do
      capture_io do
        @vs.send(:parse_options, ['--ids', 'abc', '--exclude-ids', 'def'])
      end
    end
  end
end

class XPlatformArchiveTest < Minitest::Test
  def setup
    @archive_dir = File.join(Dir.tmpdir, "vanillasky_test_archive_#{$$}")
    @data_dir = File.join(@archive_dir, 'data')
    FileUtils.mkdir_p(@data_dir)
  end

  def teardown
    FileUtils.rm_rf(@archive_dir)
  end

  def test_fetch_old_posts_from_archive
    write_tweets_js([
      make_tweet('100', 'Sat Jan 01 12:00:00 +0000 2022', 'Old post'),
      make_tweet('101', 'Sat Jan 01 12:00:00 +0000 2025', 'Recent post'),
      make_tweet('102', 'Sat Jan 01 12:00:00 +0000 2022', 'Old reply', in_reply_to: '99'),
      make_tweet('103', 'Sat Jan 01 12:00:00 +0000 2022', 'RT @someone: retweeted')
    ])

    platform = XPlatform.new(@archive_dir)
    cutoff = Date.new(2024, 1, 1)

    posts = platform.fetch_old_posts(cutoff, nil, [])

    assert_equal 1, posts.length
    assert_equal '100', posts[0][:uri]
    assert_equal 'Old post', posts[0][:text]
  end

  def test_fetch_old_replies_from_archive
    write_tweets_js([
      make_tweet('100', 'Sat Jan 01 12:00:00 +0000 2022', 'Not a reply'),
      make_tweet('101', 'Sat Jan 01 12:00:00 +0000 2022', 'A reply', in_reply_to: '99')
    ])

    platform = XPlatform.new(@archive_dir)
    cutoff = Date.new(2024, 1, 1)

    replies = platform.fetch_old_replies(cutoff, nil, [])

    assert_equal 1, replies.length
    assert_equal '101', replies[0][:uri]
  end

  def test_fetch_old_reposts_from_archive
    write_tweets_js([
      make_tweet('100', 'Sat Jan 01 12:00:00 +0000 2022', 'Normal post'),
      make_tweet('101', 'Sat Jan 01 12:00:00 +0000 2022', 'RT @user: some retweet')
    ])

    platform = XPlatform.new(@archive_dir)
    cutoff = Date.new(2024, 1, 1)

    reposts = platform.fetch_old_reposts(cutoff, nil, [])

    assert_equal 1, reposts.length
    assert_equal '101', reposts[0][:uri]
  end

  def test_fetch_old_likes_from_archive
    # Use a snowflake ID that decodes to a date before the cutoff
    # ID 1477000000000000000 => approx Dec 31 2021
    # ID 1800000000000000000 => approx Sep 2024
    write_likes_js([
      { 'tweetId' => '1477000000000000000', 'fullText' => 'Old liked tweet' },
      { 'tweetId' => '1800000000000000000', 'fullText' => 'Recent liked tweet' }
    ])

    platform = XPlatform.new(@archive_dir)
    cutoff = Date.new(2024, 6, 1)

    likes = platform.fetch_old_likes(cutoff, nil, [])

    assert_equal 1, likes.length
    assert_equal '1477000000000000000', likes[0][:uri]
  end

  def test_excludes_ids
    write_tweets_js([
      make_tweet('100', 'Sat Jan 01 12:00:00 +0000 2022', 'Post A'),
      make_tweet('101', 'Sat Jan 01 12:00:00 +0000 2022', 'Post B')
    ])

    platform = XPlatform.new(@archive_dir)
    cutoff = Date.new(2024, 1, 1)

    posts = platform.fetch_old_posts(cutoff, nil, ['100'])

    assert_equal 1, posts.length
    assert_equal '101', posts[0][:uri]
  end

  def test_start_date_filter
    write_tweets_js([
      make_tweet('100', 'Sat Jan 01 12:00:00 +0000 2022', 'Before start date'),
      make_tweet('101', 'Mon Jul 01 12:00:00 +0000 2023', 'After start date')
    ])

    platform = XPlatform.new(@archive_dir)
    cutoff = Date.new(2024, 1, 1)
    start_date = Date.new(2023, 1, 1)

    posts = platform.fetch_old_posts(cutoff, start_date, [])

    assert_equal 1, posts.length
    assert_equal '101', posts[0][:uri]
  end

  def test_fetch_record_by_id_tweet
    write_tweets_js([
      make_tweet('100', 'Sat Jan 01 12:00:00 +0000 2022', 'Found me')
    ])

    platform = XPlatform.new(@archive_dir)
    record = platform.fetch_record_by_id('100', 'tweet')

    assert_equal '100', record[:uri]
    assert_equal 'Found me', record[:text]
  end

  def test_fetch_record_by_id_not_found
    write_tweets_js([])

    platform = XPlatform.new(@archive_dir)
    record = platform.fetch_record_by_id('999', 'tweet')

    assert_nil record
  end

  private

  def make_tweet(id, created_at, text, in_reply_to: nil)
    tweet = {
      'id_str' => id,
      'id' => id,
      'created_at' => created_at,
      'full_text' => text
    }
    tweet['in_reply_to_status_id_str'] = in_reply_to if in_reply_to
    tweet
  end

  def write_tweets_js(tweets)
    data = tweets.map { |t| { 'tweet' => t } }
    File.write(
      File.join(@data_dir, 'tweets.js'),
      "window.YTD.tweet.part0 = #{JSON.generate(data)}"
    )
  end

  def write_likes_js(likes)
    data = likes.map { |l| { 'like' => l } }
    File.write(
      File.join(@data_dir, 'like.js'),
      "window.YTD.like.part0 = #{JSON.generate(data)}"
    )
  end
end
