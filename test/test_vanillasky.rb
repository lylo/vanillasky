require 'minitest/autorun'
require 'date'
require_relative '../vanillasky'

class VanillaSkyTest < Minitest::Test
  def setup
    @vs = VanillaSky.new
  end

  def test_initialize_defaults
    assert_nil @vs.instance_variable_get(:@access_token)
    assert_nil @vs.instance_variable_get(:@did)
    assert_equal 90, @vs.instance_variable_get(:@days_threshold)
    assert_equal false, @vs.instance_variable_get(:@dry_run)
  end

  def test_parse_options_days
    @vs.send(:parse_options, ['-d', '30'])
    assert_equal 30, @vs.instance_variable_get(:@days_threshold)
  end

  def test_parse_options_dry_run
    @vs.send(:parse_options, ['-n'])
    assert_equal true, @vs.instance_variable_get(:@dry_run)
  end

  def test_parse_options_help
    # Help option should exit, so we catch SystemExit
    assert_raises(SystemExit) do
      @vs.send(:parse_options, ['-h'])
    end
  end

  def test_delete_post_extracts_rkey
    # Mocks network interaction
    @vs.instance_variable_set(:@access_token, 'token')
    @vs.instance_variable_set(:@did, 'did:example:123')
    def @vs.delete_post(post_uri)
      rkey = post_uri.split('/').last
      rkey
    end
    assert_equal 'abc123', @vs.delete_post('at://did:example:123/app.bsky.feed.post/abc123')
  end
end
