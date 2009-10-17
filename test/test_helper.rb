unless Object.const_defined?(:WarnFilter) || ENV['WARN_FILTER'] == "false"
  
  # Filter warnings from vendored projects
  module WarnFilter
    VENDOR_DIR = File.expand_path(File.join(File.dirname(__FILE__), "../vendor/gems/gems"))
  
    def write(obj)
      super unless obj.rindex(VENDOR_DIR) == 0
    end
  
    $stderr.extend(self)
  end
end

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
      Grit.debug = false
    end

    def debug!
      Grit.debug = true
    end
    
    # Copies the repo over from fixtures into a temporary directory and
    # returns the repo_path.  Note the repo is cleaned up upon teardown.
    def setup_repo(repo, repo_path=nil) # :yields: repo_path
      src = File.expand_path(repo, FIXTURE_DIR)
      repo_path ||= method_root.prepare(:tmp, ".git")
      
      if File.exists?(repo_path)
        flunk("repo already exists: #{repo_path}")
      end
      
      FileUtils.cp_r(src, repo_path)
      repo_path
    end
  end
end

