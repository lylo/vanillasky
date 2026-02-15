require 'minitest/autorun'
require 'date'
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

  def test_create_platform_unknown
    @vs.instance_variable_set(:@platform_name, 'twitter')
    assert_raises(SystemExit) do
      capture_io do
        @vs.send(:create_platform)
      end
    end
  end

  def test_version
    assert_equal '0.3.0', VanillaSky::VERSION
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
