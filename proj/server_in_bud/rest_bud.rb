require 'webrick'
require 'json'

module Bud
  alias_method :old_init, :initialize
  def initialize(options={})
    old_init(options)

    if options[:rest_port]
      @server_thread = Thread.new do
        $bud_instance = self
        server = WEBrick::HTTPServer.new Port: options[:rest_port]
        server.mount "/", BudServlet
        trap('INT') { server.stop }
        server.start
      end
    end
  end

  class BudServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "tables"
          response.body = { tables: non_builtin_collections(Bud::BudTable) }.to_json
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
      rescue Exception => e
        response.body = error_response(e.message)
      end
    end

    def do_POST(request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        case action
        when "add_collection"
          handle_add_collection_req(request, response)
        # when "reset"
        #  $bud_instance = BudInstance.new
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
      rescue Exception => e
        response.body = error_response(e.message)
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
      params = JSON.parse(request.query["params"])
      ['type', 'name', 'keys', 'values'].each do |q|
        raise "Missing required arguments" unless params.include? q
      end

      # parse keys and values columns
      key_cols = params['keys'].map(&:to_sym)
      val_cols = params['values'].map(&:to_sym)

      case params['type']
      when "table"
        $bud_instance.table params['name'].to_sym, key_cols => val_cols
        response.body = { success: "Added table" }.to_json
      when "scratch"
      when "interface"
      when "channel"
      else
        raise "Unrecognized type of collection to add"
      end
    end

    private
    def error_response(message)
      { errors: message }.to_json
    end
  end
end

