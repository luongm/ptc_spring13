require 'rubygems'
require 'bud'
require 'rest_bud'
require 'test/unit'
require 'rest-client'
require 'rest_bud_helper'

class TestRestBud < Test::Unit::TestCase
  @@port = 3000

  def error_message(msg, data=nil)
    "[#{@action} /#{@resource}]: #{msg} #{"(#{data})" unless data.nil?}"
  end

  def assert_response_contains(response, key)
    assert response.include?(key), error_message("Expected response to contain #{key}", response)
  end

  def url(resource)
    "http://localhost:#{@@port}/#{resource}"
  end

  def options(params)
    { params: params.to_json, content_type: :json, accept: :json }
  end

  def parse_response(response)
    assert_equal 200, response.code
    return JSON.parse response.strip
  end

  def get(resource, params={})
    @action = 'GET'
    @resource = resource
    return parse_response(RestClient.get url(resource), options(params))
  end

  def post(resource, params={})
    @action = 'POST'
    @resource = resource
    return parse_response(RestClient.post url(resource), options(params))
  end

  def delete (resource, params={})
    @action = 'DELETE'
    @resource = resource
    return parse_response(RestClient.delete url(resource), options(params))
  end

  def assert_contents(table, contents)
    assert_equal contents.size, table.length
    contents.each do |e|
      assert table.include?(e), "Expected row #{e} to appear in table #{table}"
    end
  end

  # Bud methods
  def tables
    @bud_inst.tables
  end

  def get_rules
    $bud_instance.t_rules.to_a.map {|x| x[5]}
  end

  def assert_has_rule(lhs, op, rhs)
    # NOTE this will sometimes fail because the rhs of rule might get rewritten
    rule = "#{lhs} #{op} (#{rhs})"
    assert get_rules.include?(rule), "Rule '#{rule}' not found in #{get_rules}"
  end

  # REST methods
  def rest_add_collection(name, type, keys, values)
    data = post :add_collection, collection_name: name, type: type, keys: keys, values: values
    assert_response_contains(data, 'success')
    assert tables.include?(name), "[POST /add_collection]: Bud instance should include the added table's name"
    return data
  end

  def rest_get_collections
    data = get :collections
    assert_response_contains(data, 'collections')
    return data['collections']
  end

  def rest_get_collection_content(tabname)
    data = get :content, { collection_name: tabname }
    assert_response_contains(data, 'content')
    return data['content']
  end

  def rest_insert_rows(collection, op, rows)
    data = post :add_rows, collection_name: collection, op: op, rows: rows
    assert_response_contains(data, 'success')
    assert_equal "Added rows to collection '#{collection}'", data['success']
  end

  def rest_remove_rows(collection_name, rows)
    data = delete :remove_rows, collection_name: collection_name, rows: rows
    assert_response_contains(data, 'success')
    assert_equal "Removed rows from collection '#{collection_name}'", data['success']
  end

  def rest_get_rules
    data = get :rules
    assert_response_contains(data, 'rules')
    return data['rules']
  end

  def rest_add_rule(lhs, op, rhs)
    data = post :add_rule, lhs: lhs, op: op, rhs: rhs
    assert_response_contains(data, 'success')
    assert_equal 'Added rule to bud', data['success']
  end

  def rest_tick(times=nil)
    data = if times
      post :tick, times: times
    else
      post :tick
    end
    assert_response_contains(data, 'success')
    assert_equal "Ticked the bud instance #{times or 1} times", data['success']
  end

  def setup
    c = Class.new do
      include Bud
      include BudRestHelper
    end
    Kernel.const_set 'RestBud', c

    @@port = @@port+1
    @bud_inst = RestBud.new
    @rest_bud = BudRESTServer.new RestBud, @bud_inst, @@port
    @bud_inst.start
    sleep 1
  end

  def teardown
    @bud_inst.stop
    @rest_bud.stop
  end

  def test_basic
    # test data
    tabname = :test_table
    key_cols = [:test_key_1, :test_key_2]
    val_cols = [:test_val_1, :test_val_2]
    rows = 4.times.map { |i| ["k#{i}a", "k#{i}b", "v#{i}a", "v#{i}b"] } # ['k1a', 'k1b', 'v1a', 'v1b']

    # POST /add_collection
    rest_add_collection tabname, :table, key_cols, val_cols

    assert_equal key_cols, tables[tabname].key_cols
    assert_equal val_cols, tables[tabname].val_cols

    # GET /collections
    assert_equal rest_get_collections, {'tables' => [tabname.to_s]}

    # POST /add_rows with <=
    rest_insert_rows tabname, '<=', rows[0..1]
    assert_contents tables[tabname], rows[0..1]

    # GET /content
    assert_contents rest_get_collection_content(tabname), rows[0..1]

    # DELETE /remove
    rest_remove_rows(tabname, [rows[0]])
    assert_contents tables[tabname], rows[0..1]
    rest_tick(2) # NOTE doesn't remove if only tick once
    assert_contents tables[tabname], rows[1..1]

    # POST /add_rows with <+
    rest_insert_rows tabname, '<+', rows[2..2]
    assert_contents tables[tabname], rows[1..1]
    rest_tick
    assert_contents tables[tabname], rows[1..2]

    # POST /add_rows with <~
    rest_insert_rows :stdio, '<~', [[rows]]
    puts rows.inspect
    out = capture_stdout do
      rest_tick
    end
    assert_equal rows.flatten.join("\n") + "\n", out.string, "All rows should be printed out when 'stdio <~ [[rows]]'"
  end

  def test_add_collections
    # test data
    key_cols = [:test_key]
    val_cols = [:test_val]

    # Add different kinds of collections: table, scratch, input/output interface, channel
    rest_add_collection :table1, :table, key_cols, val_cols
    rest_add_collection :scratch1, :scratch, key_cols, val_cols
    rest_add_collection :input1, :input_interface, key_cols, val_cols
    rest_add_collection :output1, :output_interface, key_cols, val_cols
    rest_add_collection :channel1, :channel, key_cols+[:@loc], val_cols

    # Get the list of collections
    assert_equal rest_get_collections, {
        'tables' => ['table1'],
        'scratches' => ['scratch1'],
        'input_interfaces' => ['input1'],
        'output_interfaces' => ['output1'],
        'channels' => ['channel1']
    }
  end

  def test_add_rule
    # test data
    tabnames = 3.times.map { |i| "test_table_#{i}".to_sym }
    key_cols = [:test_key]
    val_cols = [:test_val]
    rows = 4.times.map { |i| ["k#{i}", "v#{i}"] }

    tabnames.each do |tabname|
      rest_add_collection tabname, :table, key_cols, val_cols
    end
    rest_insert_rows tabnames[0], '<=', rows[0..1]
    rest_insert_rows tabnames[1], '<=', rows[1..2]

    # POST /add_rule
    rest_add_rule tabnames[2], '<=', tabnames[0]
    assert_has_rule tabnames[2], '<=', tabnames[2]

    # check content of tabnames[2]
    rest_tick # TODO fails here
    assert_contents tables[tabnames[2]], rows[0..2]
  end
end
