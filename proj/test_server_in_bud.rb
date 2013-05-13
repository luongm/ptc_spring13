require 'rubygems'
require 'bud'
require 'rest_bud'
require 'test/unit'
require 'rest-client'

class RestBud
  include Bud
end


class TestRestBud < Test::Unit::TestCase
  def get(resource, params=nil)
    response = RestClient.get "http://localhost:#{@port}/#{resource}", params: params, content_type: :json, accept: :json
    assert_equal 200, response.code
    data = JSON.parse response.strip
    return data
  end

  def post(resource, params=nil)
    response = RestClient.post "http://localhost:#{@port}/#{resource}", params: params.to_json, content_type: :json, accept: :json
    assert_equal 200, response.code
    data = JSON.parse response.strip
    return data
  end

  def delete (resource, params=nil)
    response = RestClient.delete "http://localhost:#{@port}/#{resource}", data: params.to_json, content_type: :json, accept: :json
    assert_equal 200, response.code
    data = JSON.parse response.strip
    return data
  end

  def test_basic
    # test data
    bud_inst = RestBud.new
    @port = 3000
    rest_bud = BudRESTServer.new bud_inst, rest_port: @port
    # bud_inst.run_bg

    tabname = :test_table
    key_cols = [:test_key_1, :test_key_2]
    val_cols = [:test_val_1, :test_val_2]
    rows = 4.times.map { |i| ["k#{i}a", "k#{i}b", "v#{i}a", "v#{i}b"] } # ['k1a', 'k1b', 'v1a', 'v1b']

    # POST /add_collection
    data = post :add_collection, {type: 'table', name: tabname, keys: key_cols, values: val_cols}
    assert data.include?("success"), "Did not receive success message when adding table\n '#{data.inspect}'"
    assert bud_inst.tables.include?(tabname), "Bud instance should include the added table's name"
    resp_key_cols = bud_inst.tables[tabname].key_cols
    resp_val_cols = bud_inst.tables[tabname].cols - key_cols
    assert_equal key_cols, resp_key_cols
    assert_equal val_cols, resp_val_cols

    # GET /collections
    data = get :collections
    assert data.include?("tables"), "Did not receive success message when 'GET /collections'\n '#{data.inspect}'"
    assert_equal [tabname.to_s], data["tables"]

    # POST /insert
    data = post :add_rows, { collection_name: tabname, op: '<=', rows: rows[0..1] }
    assert data.include?("success"), "Did not receive success message when add a row into '#{tabname}'\n #{data.inspect}"
    assert_equal "Added rows to collection '#{tabname}'", data["success"]
    assert_equal 2, bud_inst.tables[tabname].length
    assert bud_inst.tables[tabname].include?(rows[0]), "Expected rows #{rows[0]} to appear in table '#{tabname}' storage"
    assert bud_inst.tables[tabname].include?(rows[1]), "Expected rows #{rows[1]} to appear in table '#{tabname}' storage"

    # TODO test for <+ and <~
    # data = post :add_rows, { collection_name: tabname, op: '<~', rows: rows[2..2] }
    # 10.times { bud_inst.tick }
    # assert_equal 3, bud_inst.tables[tabname].length
    # assert bud_inst.tables[tabname].include?(rows[2]), "Expected rows #{rows[2]} to appear in table '#{tabname}' storage"

    # TODO DELETE /remove
    data = delete :remove_rows, { collection_name: tabname, rows: [rows[1]] }
    assert data.include?("success"), "Did not receive success message when remove a row from '#{tabname}'\n '#{data.each {|d| d.inspect}}'"
    assert_equal "Removed rows to collection '#{tabname}'", data["success"]
    assert_equal 1, bud_inst.tables[tabname].count, "Should only have 1 row now"
    assert bud_inst.tables[tabname].include?(rows[0]), "Expected rows #{rows[0]} to appear in table '#{tabname}' storage"
    assert !bud_inst.tables[tabname].include?(rows[1]), "Expected rows #{rows[1]} to appear in table '#{tabname}' storage"
  end

  def test_add_rule
    # test data
    bud_inst = RestBud.new
    @port = 3001
    rest_bud = BudRESTServer.new bud_inst, rest_port: @port
    # bud_inst.run_bg

    tabname1 = :test_table_1
    tabname2 = :test_table_2
    key_cols = [:test_key]
    val_cols = [:test_val]
    rows = 4.times.map { |i| ["k#{i}", "v#{i}"] } # ['k1', 'v1']

    # POST /add_collection
    post :add_collection, {type: 'table', name: tabname1, keys: key_cols, values: val_cols}
    post :add_collection, {type: 'table', name: tabname2, keys: key_cols, values: val_cols}
    post :add_rows, { collection_name: tabname1, op: '<=', rows: rows[0..1] }
    data = post :add_rule, { lhs: tabname1, op: '<=', rhs: tabname2 } 
    assert data.include?("success"), "Did not receive success message when adding a rule\n '#{data.each {|d| d.inspect}}'"
    assert_equal "Added rule to bud", data["success"]
  end
end

