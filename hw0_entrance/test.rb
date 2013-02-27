require 'rubygems'

if ENV["COVERAGE"]
  require 'simplecov'
  SimpleCov.command_name 'minitest'
  SimpleCov.root '..'
  SimpleCov.start
end

gem 'minitest'
require 'rest-client'
require 'json'

require 'minitest/autorun'

SINGLE_SERVER = "ec2-54-241-78-34.us-west-1.compute.amazonaws.com:8080"
REP_SERVERS = ["ec2-184-169-190-253.us-west-1.compute.amazonaws.com:8080",
               "ec2-184-169-210-186.us-west-1.compute.amazonaws.com:8080",
               "ec2-184-169-254-236.us-west-1.compute.amazonaws.com:8080"]

VERBS = {start_auction: :post,
         bid: :post,
         status: :get,
         winner: :get,
         rst: :post}

class TestAuction < MiniTest::Unit::TestCase
  def do_rest(host, resource, params=nil)
    if VERBS[resource] == :get
      RestClient.get("http://#{host}/#{resource}", {params: params})
    elsif VERBS[resource] == :post
      RestClient.post("http://#{host}/#{resource}", params)
    end
  end

  def reset(servers)
    servers.each { |server|
      do_rest(server, :rst)
    }
  end
  def all_servers
    [SINGLE_SERVER] + REP_SERVERS
  end

  def test_single_server
    reset([SINGLE_SERVER])
    server = SINGLE_SERVER
    name = "gau1"
    res = do_rest(server, :start_auction, {name: name, end_time: Time.now.to_i + 3})
    assert_equal("None", res.strip)

    res = do_rest(server, :status, {name: name})
    assert_equal("UNKNOWN", res.strip)

    res = do_rest(server, :bid, {name: name, client: 1, bid: 100})
    assert_equal("None", res.strip)

    res = do_rest(server, :status, {name: name})
    assert_equal("1", res.strip)

    res = do_rest(server, :winner, {name: name})
    assert_equal("UNKNOWN", res.strip)

    # series of valid bids
    res = do_rest(server, :bid, {name: name, client: 2, bid: 300})
    assert_equal("None", res.strip)
    
    res = do_rest(server, :bid, {name: name, client: 3, bid: 400})
    assert_equal("None", res.strip)

    res = do_rest(server, :bid, {name: name, client: 4, bid: 100})
    assert_equal("None", res.strip)

    # status and winner
    res = do_rest(server, :status, {name: name})
    assert_equal("3", res.strip)

    res = do_rest(server, :winner, {name: name})
    assert_equal("UNKNOWN", res.strip)

    # wait til auction's over
    sleep 4
    res = do_rest(server, :winner, {name: name})
    assert_equal("3", res.strip)

    # invalidly start an auction with same name
    res = do_rest(server, :start_auction, {name: name, end_time: Time.now.to_i + 3})
    assert_equal("None", res.strip)

    # should yield same winner
    res = do_rest(server, :winner, {name: name})
    assert_equal("3", res.strip)
  end

  def test_inquisitor
    reset(REP_SERVERS)
    server = REP_SERVERS[0]
    do_rest(server, :start_auction, {name: "anchovies", end_time: Time.now.to_i + 3})
    do_rest(server, :bid, {name: "anchovies", client: 1, bid: 100})
    do_rest(server, :bid, {name: "anchovies", client: 2, bid: 300})
    do_rest(server, :bid, {name: "anchovies", client: 1, bid: 400})
    
    # running winner
    res = do_rest(server, :status, {name: "anchovies"})
    assert_equal("1", res.strip)

    # no absolute winner
    res = do_rest(server, :winner, {name: "anchovies"})
    assert_equal("UNKNOWN", res.strip)

    sleep 5
    res = do_rest(server, :winner, {name: "anchovies"})
    assert_equal("1", res.strip)
  end

  # Send request to server1 first then check server2 and server3 for replication
  def test_start_auction_to_one_server_should_replicate
    reset(REP_SERVERS)
    server1, server2, server3 = REP_SERVERS
    name = "gau2"
    
    do_rest(server1, :start_auction, {name: name, end_time: Time.now.to_i + 3})
    do_rest(server1, :bid, {name: name, client:1, bid:100})
    res = do_rest(server1, :status, {name: name})
    assert_equal("1", res.strip)

    res = do_rest(server2, :status, {name: name})
    assert_equal("1", res.strip)
    res = do_rest(server3, :status, {name: name})
    assert_equal("1", res.strip)
  end

  def test_start_auctions_with_different_ending_times_to_different_servers
    reset(REP_SERVERS)
    server1, server2, server3 = REP_SERVERS
    name = "gau3"
    do_rest(server1, :start_auction, {name: name, end_time: Time.now.to_i + 3})
    do_rest(server2, :start_auction, {name: name, end_time: Time.now.to_i + 10})

    res = do_rest(server3, :bid, {name: name, bid: 500, client: 1})
    sleep 5
    res = do_rest(server3, :bid, {name: name, bid: 700, client: 2})

    res = do_rest(server3, :status, {name: name})
    assert_equal("1", res.strip)
  end

  def test_two_clients_bid_for_the_same_price
    reset(REP_SERVERS)
    server1, server2, server3 = REP_SERVERS
    name = "gau4"
    do_rest(server1, :start_auction, {name: name, end_time: Time.now.to_i + 3})
    do_rest(server2, :bid, {name: name, bid: 100, client: 1}) # dummy bid
    do_rest(server2, :bid, {name: name, bid: 300, client: 2}) # same bid no.1
    do_rest(server3, :bid, {name: name, bid: 300, client: 3}) # same bid no.2
    sleep 4

    # test for integrity between servers after auctions are over
    res1 = do_rest(server1, :status, {name: name})
    res2 = do_rest(server2, :status, {name: name})
    res3 = do_rest(server3, :status, {name: name})
    assert_equal(res1.strip, res2.strip)
    assert_equal(res2.strip, res3.strip)
    assert_equal("2", res1.strip)
  end
end

