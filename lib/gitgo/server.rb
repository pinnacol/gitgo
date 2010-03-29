require 'gitgo/constants'
require 'gitgo/app'
require 'rack/server'

module Gitgo
  class Session
    attr_reader :app
    attr_reader :session
    attr_reader :session_env
    
    def initialize(app, session_env)
      @app = app
      @session = {}
      @session_env = session_env
      @session_env['rack.session'] = @session
    end
    
    def call(env)
      env.merge!(session_env)
      app.call(env)
    end
  end
  
  # Only for use by bin/gitgo; config.ru should be constructed differently
  # to accomodate sessions.
  class Server < Rack::Server
    
    def app
      # set the controller environment; this should propagate to
      # all the gitgo controllers + app
      Controller.set(:environment, options[:environment].to_sym)
      
      repo = Repo.init(options[:repo], options)
      Session.new(App, Gitgo::REPO_ENV_VAR => repo, Gitgo::MOUNT_ENV_VAR => options[:mount])
    end
    
    def default_options
      {
        :environment => "development",
        :pid         => nil,
        :Port        => 8080,
        :Host        => "0.0.0.0",
        :AccessLog   => [],
        
        # gitgo-specific
        :repo        => ".",
        :branch      => "gitgo",
        :mount       => nil
      }
    end
    
    private
    
    def parse_options(args)
      options = default_options
      opt_parser = OptionParser.new("", 24, '  ') do |opts|
        opts.banner = "usage: gitgo [options]"
        opts.separator ""
        opts.separator "options:"

        opts.on("-s", "--server SERVER", "serve using SERVER (webrick/mongrel)") { |s|
          options[:server] = s
        }

        opts.on("-o", "--host HOST", "listen on HOST (default: #{options[:Host]})") { |host|
          options[:Host] = host
        }

        opts.on("-p", "--port PORT", "use PORT (default: #{options[:Port]})") { |port|
          options[:Port] = port
        }
        
        opts.on("-r", "--repo=REPO_ENV_VAR", "use git repo (default: #{options[:repo]})") { |repo|
          options[:repo] = repo
        }

        opts.on("-b", "--branch=BRANCH", "use gitgo branch (default: #{options[:branch]})") { |branch|
          options[:branch] = branch
        }
        
        opts.on("-E", "--env ENVIRONMENT", "use ENVIRONMENT for defaults (default: #{options[:environment]})") { |e|
          options[:environment] = e
        }
        
        opts.on("-D", "--daemonize", "run daemonized in the background") { |d|
          options[:daemonize] = d ? true : false
        }

        opts.on("-P", "--pid FILE", "file to store PID (default: rack.pid)") { |f|
          options[:pid] = f
        }
        
        opts.on("-d", "--debug", "set debugging flags (set $DEBUG to true)") {
          options[:debug] = true
        }
        
        opts.on("-w", "--warn", "turn warnings on for your script") {
          options[:warn] = true
        }

        opts.on_tail("-h", "--help", "Show this message") {
          puts opts
          exit(0)
        }
        
        opts.separator ""
        opts.separator "version #{Gitgo::VERSION} -- #{Gitgo::WEBSITE}"
      end
      
      opt_parser.parse!(args)
      options
    end
  end
end