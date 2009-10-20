require 'erb'
require 'redcloth'
require 'sinatra/base'

module Gitgo
  class Controller < Sinatra::Base
    class << self
      # The Gitgo repo, by default initialized to '.'.
      def repo
        @repo ||= Repo.init
      end
      
      # The resource name (ex 'blob', 'tree', 'commit')
      attr_accessor :resource_name
      
      private
      
      # Overridden to make routes relative to the resource name, if it is set.
      def route(verb, path, options={}, &block)
        if resource_name
          # The root path needs to be dealt with a little special in nested
          # resources.  Both '/name' and '/name/' are considered root paths
          # to the nested resource; the latter is added here.
          super(verb, "/#{resource_name}/", options, &block) if path == "/"
          path = File.join("/#{resource_name}", path).chomp("/")
        end
        
        super(verb, path, options, &block)
      end
    end
    
    set :root, File.expand_path(File.dirname(__FILE__) + "/../..")
    set :raise_errors, false
    set :dump_errors, true
    set :resource_name, nil
    set :repo, nil
    
    attr_reader :repo
    
    def initialize(app=nil, repo=nil)
      super(app)
      @repo = repo || options.repo
    end
    
    template(:layout) do 
      File.read("views/layout.erb")
    end
    
    not_found do
      erb :not_found, :views => "views"
    end
    
    error Exception do
      erb :error, :views => "views", :locals => {:err => env['sinatra.error']}
    end
    
    protected
    
    def url(path="/")
      return path unless resource_name = options.resource_name
      path == "/" ? "/#{resource_name}" : File.join("/#{resource_name}", path)
    end
    
    # Returns a title for pages served from this controller; either the
    # capitalized resource name or the class basename.
    def title
      name = options.resource_name || self.class.to_s.split("::").last
      name.capitalize
    end
    
    # Renders template as erb, then formats using RedCloth.
    def textile(template, options={}, locals={})
      require_warn('RedCloth') unless defined?(::RedCloth)
      
      # extract generic options
      layout = options.delete(:layout)
      layout = :layout if layout.nil? || layout == true
      views = options.delete(:views) || self.class.views || "./views"
      locals = options.delete(:locals) || locals || {}

      # render template
      data, options[:filename], options[:line] = lookup_template(:textile, template, views)
      output = render_erb(template, data, options, locals)
      output = ::RedCloth.new(output).to_html
      
      # render layout
      if layout
        data, options[:filename], options[:line] = lookup_layout(:erb, layout, views)
        if data
          output = render_erb(layout, data, options, locals) { output }
        end
      end

      output
    end
  end
end