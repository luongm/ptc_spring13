require 'rubygems'
gem 'ruby_parser', '>= 3.0.2'
require 'ruby_parser'
require 'stringio'

class Class
  def add_rule(rule)
      @block_id ||= 0
      @block_id += 1

      meth_name = "__bloom__#{Module.get_class_name(self)}__#{@block_id}"

      parser = RubyParser.for_current_ruby
      ast = parser.parse rule

      if ast.nil?
          ast = []
      elsif ast.sexp_type == :block
          ast = ast.sexp_body
      else
          ast = [ast]
      end
      ast = s(:defn, meth_name.to_sym, s(:args), *ast)
      unless self.respond_to? :__bloom_asts__
          def self.__bloom_asts__
              @__bloom_asts__ ||= {}
              @__bloom_asts__
          end
      end
      __bloom_asts__[meth_name] = ast
      define_method(meth_name.to_sym, eval("proc {#{rule}}"))
  end
end

module Kernel
  def capture_stdout
    out = StringIO.new
    $stdout = out
    yield
    reset_stdout and return out
  ensure
    reset_stdout
  end
  def reset_stdout
    $stdout = STDOUT
  end
end

module BudRestHelper
  def reload
    @declarations = self.class.instance_methods.select {|m| m =~ /^__bloom__.+$/}.map {|m| m.to_s}
    do_rewrite
    if toplevel == self
      # initialize per-stratum state
      num_strata = @stratified_rules.length
      @scanners = num_strata.times.map{{}}
      @push_sources = num_strata.times.map{{}}
      @push_joins = num_strata.times.map{[]}
      @merge_targets = num_strata.times.map{Set.new}
    end
  end
end
