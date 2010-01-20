require 'erb'
require 'sinatra/base'
require 'gitgo/repo'
require 'gitgo/helpers'

module Gitgo
  # The expanded path to the Gitgo root directory, used for resolving paths to
  # views, public files, etc.
  ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")
  
  class Controller < Sinatra::Base
    class << self
      # The Gitgo repo, by default initialized to '.'. Repo is stored as a
      # class variable to make it available in all subclasses.
      def repo
        @@repo ||= Repo.init
      end
      
      # Set the repo -- the input can be the path to the repo or a Gitgo::Repo
      # instance.  Setting the repo will reinitialize the sinatra prototype.
      def repo=(input)
        @prototype = nil
        @@repo = input.kind_of?(String) ? Repo.init(input) : input
      end
      
      # The default author. Author is stored as a class variable to make it
      # available in all subclasses.
      def author
        @@author ||= repo.author
      end
      
      # Sets the default author.
      def author=(input)
        @@author = input
      end
    end
    
    set :root, ROOT
    set :raise_errors, false
    set :dump_errors, true
    set :repo, nil
    set :author, nil
    set :secret, nil
    
    template(:layout) do 
      File.read(File.join(ROOT, "views/layout.erb"))
    end
    
    helpers do
      include Helpers
    end
    
    not_found do
      erb :not_found, :views => path("views")
    end
    
    error Exception do
      erb :error, :views => path("views"), :locals => {:err => env['sinatra.error']}
    end
    
    #
    # actions
    #
    
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
    
    # Returns true if the controller has a secret and the secret is set in the
    # current request.  Always returns false if the controller has no secret.
    def admin?
      options.secret && request[SECRET] == options.secret
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
    
    # Returns the rack session.
    def session
      request ? request.env['rack.session'] : nil
    end
    
    # Returns a self-filling, per-request cache of documents.  See Repo#cache.
    def docs
      @docs ||= repo.cache
    end
    
    # Returns true if the object is nil, or as a stripped string is empty.
    def empty?(obj)
      obj.nil? || obj.to_s.strip.empty?
    end
  end
end