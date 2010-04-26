require 'erb'
require 'sinatra/base'
require 'gitgo/helper'
require 'gitgo/document'
require 'gitgo/rest'

module Gitgo
  class Controller < Sinatra::Base
    ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")
    HEAD  = 'gitgo.head'
    MOUNT = 'gitgo.mount'
    
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
    
    def initialize(app=nil, repo=nil)
      super(app)
      @repo = repo
    end
    
    # Returns the path expanded relative to the Gitgo::ROOT directory.  Paths
    # often need to be expanded like this so that they will be correct when
    # Gitgo is running as a gem.
    def path(path)
      File.expand_path(path, ROOT)
    end
    
    def repo
      @repo ||= Repo.current
    end
    
    def call(env)
      env[Repo::REPO] ||= @repo
      Repo.with_env(env) { super(env) }
    end
    
    def session_head
      # grit.head will be nil if not on a local branch
      @session_head ||= begin
        if session.has_key?(HEAD)
          session[HEAD]
        else
          grit = repo.git.grit
          session[HEAD] = grit.head ? grit.head.name : nil
        end
      end
    end
    
    def session_head=(input)
      @session_head = session[HEAD] = input
    end
    
    def mount_point
      @mount_point ||= (env[MOUNT] || '/')
    end
    
    def url(paths)
      File.join(mount_point, *paths)
    end
    
    def format
      @format ||= Helper::Format.new(self)
    end
    
    def form
      @form ||= Helper::Form.new(self)
    end
    
    def html
      Helper::Html
    end
  end
end