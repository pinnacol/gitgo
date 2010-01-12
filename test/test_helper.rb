require 'vendor/gems/environment'

# Filter warnings from bundled projects
module WarnFilter
  VENDOR_DIR = File.expand_path(File.join(File.dirname(__FILE__), "../vendor/gems"))

  def write(obj)
    super unless obj.rindex(VENDOR_DIR) == 0
  end
  
  unless ENV['WARN_FILTER'] == "false"
    $stderr.extend(self)
  end
end unless Object.const_defined?(:WarnFilter)

require 'tap/test/unit'
require 'rack/test'

unless Object.const_defined?(:RepoTestHelper)
  
  # Sets git repositories for testing.
  module RepoTestHelper
    FIXTURE_DIR = File.expand_path(File.dirname(__FILE__) + "/fixtures")
    
    def self.included(base)
      # sets the root to 'test/x' when included in
      # classes defined in 'test/x_test.rb'
      calling_file = caller[1].gsub(/:\d+(:in .*)?$/, "")
      calling_file = calling_file.chomp(File.extname(calling_file)).chomp("_test")
      
      base.acts_as_file_test(:root => calling_file)
    end
    
    def setup
      super
      Grit.debug = false if Object.const_defined?(:Grit)
    end

    def debug!
      Grit.debug = true
    end
    
    # Copies the repo over from fixtures into a temporary directory and
    # returns the repo_path.  Note the repo is cleaned up upon teardown.
    def setup_repo(repo, repo_path=nil) # :yields: repo_path
      src = File.expand_path(repo, FIXTURE_DIR)
      repo_path ||= method_root.path(:tmp, ".git")
      
      if File.exists?(repo_path)
        flunk("repo already exists: #{repo_path}")
      end
      
      dir = File.dirname(repo_path)
      unless File.exists?(dir)
        FileUtils.mkdir_p(dir)
      end
      
      FileUtils.cp_r(src, repo_path)
      repo_path
    end
    
    def sh(dir, cmd, env={})
      current = {}
      begin
        ENV.keys.each do |key|
          if key =~ /^GIT_/
            current[key] = ENV.delete(key)
          end
        end

        env.each_pair do |key, value|
          current[key] ||= nil
          ENV[key] = value
        end

        Dir.chdir(dir) do
          puts "% #{cmd}" if ENV['DEBUG'] == 'true'
          path = method_root.prepare(:tmp, 'stdout')
          system("#{cmd} > '#{path}' 2>&1")

          output = File.exists?(path) ? File.read(path) : nil
          puts output if ENV['DEBUG'] == 'true'
          output.chomp
        end

      ensure
        current.each_pair do |key, value|
          if value
            ENV[key] = value
          else
            ENV.delete(key)
          end
        end
      end
    end
  end
end

