require 'erb'
require 'sinatra/base'
require 'gitgo/repo'

module Gitgo
  # The expanded path to the Gitgo root directory, used for resolving paths to
  # views, public files, etc.
  ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")
  
  class Controller < Sinatra::Base
    set :root, ROOT
    set :raise_errors, false
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
    
    #
    # actions
    #
    
    # The standard document content parameter
    CONTENT = 'content'
    
    # The standard document attributes parameter
    ATTRIBUTES = 'doc'
    
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
      @repo ||= request.env['gitgo.repo']
    end
    
    # Convenience method; memoizes and returns the repo author.
    def author
      @author ||= repo.author
    end
    
    # Convenience method; memoizes and returns the repo grit object.
    def grit
      @grit ||= repo.grit
    end
    
    # Convenience method; memoizes and returns the repo cache.
    def cache
      @cache ||= repo.cache
    end
    
    # Currently returns the path directly.  Provided as a hook for future use.
    def url(path="/")
      path
    end
    
    # Returns the path expanded relative to the Gitgo::ROOT directory.  Paths
    # often need to be expanded like this so that they will be correct when
    # Gitgo is running as a gem.
    def path(path)
      File.expand_path(path, ROOT)
    end
    
    # Returns true if the key is 'true' in the request parameters.
    def set?(key)
      request[key].to_s == 'true'
    end
    
    # Returns true if the object is nil, or as a stripped string is empty.
    def empty?(obj)
      obj.nil? || obj.to_s.strip.empty?
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
  end
end