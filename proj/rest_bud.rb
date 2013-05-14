gem 'ruby_parser', '>= 3.0.2'
require 'ruby_parser'
require 'webrick'
require 'json'

class BudRESTServer
  def initialize(klass, bud_instance, options={})
    $bud_class = RestBud
    $bud_instance = bud_instance
    $rule_num = 0

    if options[:rest_port]
      @server_thread = Thread.new do
        @server = WEBrick::HTTPServer.new Port: options[:rest_port]
        @server.mount "/", BudServlet
        trap('INT') { @server.stop }
        @server.start
      end
    end
  end

  def stop
    @server.stop
  end

  class BudServlet < WEBrick::HTTPServlet::AbstractServlet
    @@get_routes = {
      'collections' => :get_collections,
      'content' => :get_content,
      'rules' => :get_rules
    }
    @@post_routes = {
      'add_collection' => :add_collection,
      'add_rows' => :add_rows,
      'add_rule' => :add_rule
    }
    @@delete_routes = {
      'remove_rows' => :remove_rows
    }

    def handle_request(routes, request, response)
      response.status = 200
      begin
        action = request.path[1..-1].split("/")[0]
        if routes.include? action
          self.send(routes[action], request)
          response.body = @response.to_json
        else
          raise "Unrecognized action '#{action}' in path '#{request.path}'"
        end
      rescue Exception => e
        response.body = error_response(e.message)
      end
    end

    def do_GET(request, response)
      parse_header_params request
      handle_request(@@get_routes, request, response)
    end

    def do_POST(request, response)
      parse_query_params request
      handle_request(@@post_routes, request, response)
    end

    def do_DELETE(request, response)
      parse_header_params request
      handle_request(@@delete_routes, request, response)
    end

    private
    # GET methods
    def get_collections(request)
      names = $bud_instance.tables.keys - $bud_instance.builtin_tables.keys
      collections = {}
      {
        :tables => Bud::BudTable,
        :scratches => Bud::BudScratch,
        :input_interfaces => Bud::BudInputInterface,
        :output_interfaces => Bud::BudOutputInterface,
        :channels => Bud::BudChannel
      }.each do |sym, klass|
        results = names.select { |name| name if $bud_instance.tables[name].class == klass }
        collections[sym] = results unless results.empty?
      end
      @response = { collections: collections }
    end

    def get_content(request)
      require_param_keys ['collection_name']
      collection_name = @params['collection_name']
      @response = { content: get_collection(collection_name).to_a.map(&:to_a) }
    end

    def get_rules(request)
      @response = { rules: $bud_instance.t_rules.to_a.map {|x| x[5]} }
    end

    # POST methods
    def add_collection(request)
      require_param_keys ['type', 'collection_name', 'keys', 'values']

      # parse keys and values columns
      collection_type = @params['type']
      collection_name = @params['collection_name']
      key_cols = @params['keys'].map(&:to_sym)
      val_cols = @params['values'].map(&:to_sym)

      args = [collection_name.to_sym, {key_cols => val_cols}]
      collection_map = {
        'table' => :table,
        'scratch' => :scratch,
        'input_interface' => :interface,
        'output_interface' => :interface,
        'channel' => :channel
      }
      args_map = {
        'table' => args,
        'scratch' => args,
        'input_interface' => [true] + args,
        'output_interface' => [false] + args,
        'channel' => args
      }
      if collection_map.include? collection_type
        $bud_instance.send(collection_map[collection_type], *args_map[collection_type])
      else
        raise 'Unrecognized type of collection to add'
      end
      @response = { success: "Added #{collection_type.gsub /_/, ' '} '#{collection_name}'" }
    end

    def add_rows(request)
      require_param_keys ['collection_name', 'op', 'rows']
      collection = get_collection(@params['collection_name'])

      rows = @params['rows']
      case @params['op']
      when '<='
        collection <= rows
        collection.flush_deltas
      when '<+'
        # TODO
        raise "Unemplemented feature"
      when '<~'
        # TODO
        raise "Unemplemented feature"
      else
        raise "Unexpected operation: '#{@params['op']}'"
      end
      @response = { success: "Added rows to collection '#{collection.tabname}'" }
    end

    def add_rule(request)
      require_param_keys ['lhs', 'op', 'rhs']

      $bud_class.add_rule "#{@params['lhs']} #{@params['op']} #{@params['rhs']}"
      $bud_instance.reload
      @response = { success: "Added rule to bud" }
    end

    # DELETE methods
    def remove_rows(request)
      require_param_keys ['collection_name', 'rows']
      collection = get_collection(@params['collection_name'])

      collection <- @params['rows']
      collection.tick
      @response = { success: "Removed rows from collection '#{collection.tabname}'" }
    end

    def error_response(message, backtrace=nil)
      error = { errors: message }
      error[:stack_trace] = backtrace if backtrace
      return error.to_json
    end

    def parse_header_params(request)
      @params = JSON.parse(request.header["params"][0])
    end

    def parse_query_params(request)
      @params = JSON.parse(request.query["params"])
    end

    def require_param_keys(keys)
      keys.each do |param|
        raise "Missing required argument: '#{param}'" unless @params.include? param
      end
    end

    def get_collection(collection_name)
      collection = $bud_instance.tables[collection_name.to_sym]
      raise "Collection '#{collection_name} does not exist!" if collection.nil?
      return collection
    end
  end
end
