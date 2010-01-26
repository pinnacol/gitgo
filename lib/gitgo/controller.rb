require 'erb'
require 'sinatra/base'
require 'gitgo/repo'
require 'gitgo/helpers'

module Gitgo
  # The expanded path to the Gitgo root directory, used for resolving paths to
  # views, public files, etc.
  ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")
  REPO = 'gitgo.repo'
  
  class Controller < Sinatra::Base
    set :root, ROOT
    set :raise_errors, Proc.new { test? }
    set :dump_errors, true
    
    template(:layout) do 
      File.read(File.join(ROOT, "views/layout.erb"))
    end
    
    not_found do
      erb :not_found, :views => path("views")
    end
    
    error Exception do
      err = env['sinatra.error']
      resetable = err.kind_of?(Errno::ENOENT) && err.message =~ /No such file or directory - .*idx/
      
      erb :error, :views => path("views"), :locals => {:err => err, :resetable => resetable}
    end
    
    include Helpers

    # The standard document content parameter
    CONTENT = 'content'
    
    # The standard document attributes parameter
    ATTRIBUTES = 'doc'
    
    attr_writer :repo
    
    # Initializes a new instance of self.  The repo may also be specified as a
    # a testing convenience; normally the repo is set in the request
    # environment by upstream middleware.
    def initialize(app=nil, repo=nil)
      super(app)
      @repo = repo
    end
    
    # Returns the Gitgo::Repo specified in the env, if not already specified
    # during initialization.
    def repo
      @repo ||= request.env[REPO]
    end
    
    # Convenience method; memoizes and returns the repo grit object.
    def grit
      @grit ||= repo.grit
    end
    
    # Convenience method; memoizes and returns the repo author.
    def author
      @author ||= repo.author
    end
    
    # Convenience method; memoizes and returns the repo cache.
    def cache
      @cache ||= repo.cache
    end
    
    def active_commit
      @active_commit ||= request.env['gitgo.at'] || grit.head.commit
    end
    
    # Returns an array of session-specific active shas.
    def active_shas
      @active_shas ||= repo.rev_list(active_commit)
    end
    
    # Returns true if the sha is nil (ie unspecified) or if active_shas
    # include the sha.
    def active?(sha)
      sha.nil? || active_shas.include?(sha)
    end
    
    def admin?
      false
    end
    
    # Parses and returns the document specified in the request, according to
    # the ATTRIBUTES and CONTENT parameters.
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
    
    # Returns the path expanded relative to the Gitgo::ROOT directory.  Paths
    # often need to be expanded like this so that they will be correct when
    # Gitgo is running as a gem.
    def path(path)
      File.expand_path(path, ROOT)
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