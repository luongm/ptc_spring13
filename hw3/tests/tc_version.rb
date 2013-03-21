require 'rubygems'
require 'bud'
require 'test/unit'
require '../kvs/version'

class TestVersion < Test::Unit::TestCase
  class VersionKVS 
    include Bud
    include VersionControlKVS
  end

  def setup
    @vkvs = VersionKVS.new
    @vkvs.run_bg
  end

  def teardown
    @vkvs.stop_bg
  end

  def test_put_new_key
    acks = @vkvs.sync_callback(:kvput, [[:client1, :joe, 1, :hellerstein]], :kv_acks)
    assert_equal([[1]], acks)
  end

  def test_get_existing_key
    @vkvs.sync_callback(:kvput, [[:client1, :joe, 1, :hellerstein]], :kv_acks)
    resps = @vkvs.sync_callback(:kvget, [[2, :joe]], :kvget_response)
    assert_equal([[2, :joe, :hellerstein, 0]], resps)
  end

  def test_get_non_existing_key
    resps = @vkvs.sync_callback(:kvget, [[3, :blah]], :kvget_response)
    assert_equal([[3, :blah, nil, nil]], resps)
  end

  def test_update_existing_key
    @vkvs.sync_callback(:kvput, [[:client1, :joe, 1, :hellerstein]], :kv_acks)
    acks = @vkvs.sync_callback(:kvput, [[:client2, :joe, 2, :alvaro]], :kv_acks)
    assert_equal([[2]], acks)
    
    resps = @vkvs.sync_callback(:kvget, [[3, :joe]], :kvget_response)
    assert_equal([[3, :joe, :alvaro, 1]], resps)
  end
end
