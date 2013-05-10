require 'webrick'
require 'json'
require 'bud'

class BudInstance
  include Bud
end

class BudServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(request, response)
    response.status = 200
    action = request.path[1..-1].split("/")[0]
    case action
    when "tables"
      response.body = { tables: non_builtin_collections(Bud::BudTable) }.to_json
    else
      response.body = error_response("Unrecognized action '#{action}' in path '#{request.path}'")
    end
  end

  def do_POST(request, response)
    response.status = 200
    action = request.path[1..-1].split("/")[0]
    case action
    when "add_collection"
      handle_add_collection_req(request, response)
    when "reset"
      $bud_instance = BudInstance.new
    else
      response.body = error_response("Unrecognized action '#{action}' in path '#{request.path}'")
    end
  end

  private
  def non_builtin_collections(klass=nil)
    names = $bud_instance.tables.keys - $bud_instance.builtin_tables.keys
    if klass
      names.keep_if do |name|
        $bud_instance.tables[name].class == klass
      end
    end
  end

  private
  def handle_add_collection_req(request, response)
    case request.query['type']
    when "table"
      $bud_instance.table request.query['name'].to_sym, [:test_key] => [:test_value]
      response.body = { success: "Added table" }.to_json
    when "scratch"
    when "interface"
    when "channel"
    else
      response.body = error_response("Unrecognized type of collection to add")
    end
  end

  private
  def error_response(message)
    { errors: message }.to_json
  end
end

$bud_instance = BudInstance.new
server = WEBrick::HTTPServer.new Port: 3000
server.mount "/", BudServlet
trap('INT') { server.stop }
server.start

