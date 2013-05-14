require 'rubygems'
require 'bud'
require 'rest_bud'
require 'test/unit'
require 'rest-client'
require 'rest_bud_helper'

class RestBud
  include Bud
  include BudRestHelper
end


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

  def tables
    @bud_inst.tables
  end

  def assert_contents(table, contents)
    assert_equal contents.size, table.length
    contents.each do |e|
      assert table.include?(e), "Expected row #{e} to appear in table #{table}"
    end
  end

  def add_collection(name, type, keys, values)
    data = post :add_collection, collection_name: name, type: type, keys: keys, values: values
    assert_response_contains(data, 'success')
    assert tables.include?(name), "[POST /add_collection]: Bud instance should include the added table's name"
    return data
  end

  def get_collections
    data = get :collections
    assert_response_contains(data, 'collections')
    return data['collections']
  end

  def get_content(tabname)
    data = get :content, { collection_name: tabname }
    assert_response_contains(data, 'content')
    return data['content']
  end

  def insert_row(collection, op, rows)
    data = post :add_rows, collection_name: collection, op: op, rows: rows
    assert_response_contains(data, 'success')
    assert_equal "Added rows to collection '#{collection}'", data['success']
  end

  def remove_rows(collection_name, rows)
    data = delete :remove_rows, collection_name: collection_name, rows: rows
    assert_response_contains(data, 'success')
    assert_equal "Removed rows from collection '#{collection_name}'", data['success']
  end

  def setup
    @@port = @@port+1
    @bud_inst = RestBud.new
    @rest_bud = BudRESTServer.new @bud_inst, rest_port: @@port
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
    add_collection tabname, :table, key_cols, val_cols

    assert_equal key_cols, tables[tabname].key_cols
    assert_equal val_cols, tables[tabname].val_cols

    # GET /collections
    assert_equal get_collections, {'tables' => [tabname.to_s]}

    # POST /insert
    insert_row tabname, '<=', rows[0..1]
    assert_contents tables[tabname], rows[0..1]

    # GET /content
    assert_contents get_content(tabname), rows[0..1]

    # TODO test for <+ and <~
    # data = post :add_rows, { collection_name: tabname, op: '<~', rows: rows[2..2] }
    # assert_equal 3, @bud_inst.tables[tabname].length
    # assert @bud_inst.tables[tabname].include?(rows[2]), "Expected rows #{rows[2]} to appear in table '#{tabname}' storage"

    # DELETE /remove
    remove_rows(tabname, [rows[1]])
    assert_contents tables[tabname], [rows[0]]
  end

  def test_add_collections
    # test data
    key_cols = [:test_key]
    val_cols = [:test_val]

    # Add different kinds of collections: table, scratch, input/output interface, channel
    data = post :add_collection, {type: 'table', collection_name: :table1, keys: key_cols, values: val_cols}
    assert data.include?("success"), "Did not receive success message when adding table\n '#{data.inspect}'"
    assert @bud_inst.tables.include?(:table1), "Bud instance should include the added table's name"

    data = post :add_collection, {type: 'scratch', collection_name: :scratch1, keys: key_cols, values: val_cols}
    assert data.include?("success"), "Did not receive success message when adding scratch\n '#{data.inspect}'"
    assert @bud_inst.tables.include?(:scratch1), "Bud instance should include the added scratch's name"

    data = post :add_collection, {type: 'input_interface', collection_name: :input1, keys: key_cols, values: val_cols}
    assert data.include?("success"), "Did not receive success message when adding input interface\n '#{data.inspect}'"
    assert @bud_inst.tables.include?(:input1), "Bud instance should include the added input interface's name"

    data = post :add_collection, {type: 'output_interface', collection_name: :output1, keys: key_cols, values: val_cols}
    assert data.include?("success"), "Did not receive success message when adding output interface\n '#{data.inspect}'"
    assert @bud_inst.tables.include?(:output1), "Bud instance should include the added output interface's name"

    data = post :add_collection, {type: 'channel', collection_name: :channel1, keys: key_cols+[:@loc], values: val_cols}
    assert data.include?("success"), "Did not receive success message when adding channel\n '#{data.inspect}'"
    assert @bud_inst.tables.include?(:channel1), "Bud instance should include the added output interface's name"

    # Get the list of collections
    data = get :collections
    assert data.include?("collections"), "Expect response to include 'collections' when 'GET /collections'\n'#{data.inspect}'"
    assert_equal 5, data["collections"].count, "Should only have one type of collection"

    assert data["collections"].include?("tables"), "Type 'tables' not in list\n'#{data.inspect}'"
    assert_equal 1, data["collections"]["tables"].count, "Should only have 1 table"
    assert_equal 'table1', data["collections"]["tables"][0], "Tables list should include 'table1'"

    assert data["collections"].include?("scratches"), "Type 'scratches' not in list\n'#{data.inspect}'"
    assert_equal 1, data["collections"]["scratches"].count, "Should only have 1 scratch"
    assert_equal 'scratch1', data["collections"]["scratches"][0], "Tables list should include 'scratch1'"

    assert data["collections"].include?("input_interfaces"), "Type 'input_interfaces' not in list\n'#{data.inspect}'"
    assert_equal 1, data["collections"]["input_interfaces"].count, "Should only have 1 input interface"
    assert_equal 'input1', data["collections"]["input_interfaces"][0], "Tables list should include 'input1'"

    assert data["collections"].include?("output_interfaces"), "Type 'output_interfaces' not in list\n'#{data.inspect}'"
    assert_equal 1, data["collections"]["output_interfaces"].count, "Should only have 1 output interface"
    assert_equal 'output1', data["collections"]["output_interfaces"][0], "Tables list should include 'output1'"

    assert data["collections"].include?("channels"), "Type 'tables' not in list\n'#{data.inspect}'"
    assert_equal 1, data["collections"]["channels"].count, "Should only have 1 channel"
    assert_equal 'channel1', data["collections"]["channels"][0], "Tables list should include 'channel1'"
  end

  def test_add_rule
    # test data
    tabname1 = :test_table_1
    tabname2 = :test_table_2
    key_cols = [:test_key]
    val_cols = [:test_val]
    rows = 4.times.map { |i| ["k#{i}", "v#{i}"] } # ['k1', 'v1']

    # POST /add_collection
    p $bud_instance.t_rules.inspected
    post :add_collection, {type: 'table', collection_name: tabname1, keys: key_cols, values: val_cols}
    post :add_collection, {type: 'table', collection_name: tabname2, keys: key_cols, values: val_cols}
    post :add_rows, { collection_name: tabname1, op: '<=', rows: rows[0..1] }
    data = post :add_rule, { lhs: tabname1, op: '<=', rhs: tabname2 } 
    assert data.include?("success"), "Did not receive success message when adding a rule\n '#{data.each {|d| d.inspect}}'"
    assert_equal "Added rule to bud", data["success"]
    p $bud_instance.t_rules.inspected
  end
end

