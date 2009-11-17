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
      
      # The default author. User is stored as a class variable to make it
      # available in all subclasses.
      def author
        @@author ||= repo.author
      end
      
      def author=(input)
        @@author = input
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
    set :author, nil
    set :secret, nil
    
    template(:layout) do 
      File.read("views/layout.erb")
    end
    
    helpers do
      include Utils
    end
    
    not_found do
      erb :not_found, :views => "views"
    end
    
    error Exception do
      erb :error, :views => "views", :locals => {:err => env['sinatra.error']}
    end
    
    # The standard document content parameter
    CONTENT = 'content'
    
    # The standard document attributes parameter
    ATTRIBUTES = 'doc'
    
    # The secret parameter
    SECRET = 'secret'
    
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
    
    # Returns the active author as defined by the session author/email, or using
    # the author set for the class.
    def author
      @author ||= begin
        if session && session['author']
          Grit::Actor.from_string(session['author'])
        else
          options.author
        end
      end
    end
    
    # Returns true if the key is like 'true' in the request parameters.
    def set?(key)
      request[key].to_s =~ /\Atrue\z/i ? true : false
    end
    
    # Returns true if 'commit' is set in the request parameters.
    def commit?
      set?('commit')
    end
    
    # Returns the document specified in the request.
    def document(overrides=nil)
      attrs = request[ATTRIBUTES] || {}
      
      if admin?
        attrs['author'] ||= author
        attrs['date'] ||= Time.now
      else
        attrs['author'] = author
        attrs['date'] = Time.now
      end
      
      attrs.merge!(overrides) if overrides
      Document.new(attrs, request[CONTENT])
    end
    
    def admin?
      options.secret && request[SECRET] == options.secret
    end
    
    def session
      request ? request.env['rack.session'] : nil
    end
    
    def docs
      @docs ||= repo.cache
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