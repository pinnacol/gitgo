require 'erb'
require 'redcloth'
require 'sinatra/base'
require 'gitgo/utils'
require 'gitgo/repo'

module Gitgo
  class Controller < Sinatra::Base
    class << self
      
      # The resource name (ex 'blob', 'tree', 'commit')
      attr_accessor :resource_name
      
      # The Gitgo repo, by default initialized to '.'. Repo is stored as a
      # class variable to make it available in all subclasses.
      def repo
        @@repo ||= Repo.init
      end
      
      def repo=(input)
        @prototype = nil
        @@repo = input.kind_of?(String) ? Repo.init(input) : input
      end
      
      # The default user. User is stored as a class variable to make it
      # available in all subclasses.
      def user
        @@user ||= repo.user
      end
      
      def user=(input)
        @@user = input
      end
      
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
    set :user, nil
    
    template(:layout) do 
      File.read("views/layout.erb")
    end
    
    helpers do
      include Rack::Utils
      include Utils
    end
    
    not_found do
      erb :not_found, :views => "views"
    end
    
    error Exception do
      erb :error, :views => "views", :locals => {:err => env['sinatra.error']}
    end
    
    # Returns the Gitgo::Repo for self
    attr_reader :repo
    
    def initialize(app=nil, repo=nil)
      super(app)
      @repo = repo || options.repo
    end
    
    # Nests path under the class resource_name, if set.  Otherwise url simply
    # returns the path.
    def url(path="/")
      return path unless resource_name = options.resource_name
      path == "/" || path.nil? || path == "" ? "/#{resource_name}" : File.join("/#{resource_name}", path)
    end
    
    # Returns a title for pages served from this controller; either the
    # capitalized resource name or the class basename.
    def title
      name = options.resource_name || self.class.to_s.split("::").last
      name.capitalize
    end
    
    # Returns the active user as defined by the session user/email, or using
    # the user set for the class.
    def user
      @user ||= begin
        if session && session['user']
          Grit::Actor.from_string(session['user'])
        else
          options.user
        end
      end
    end
    
    def session
      request ? request.env['rack.session'] : nil
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