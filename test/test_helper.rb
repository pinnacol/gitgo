# Filter warnings from vendored projects
module WarnFilter
  VENDOR_DIR = File.expand_path(File.join(File.dirname(__FILE__), "../vendor"))

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
    
    # {
    #   :issue_two_comment1   => 'c1a80236d015d612d6251fca9611847362698e1c',
    #   :commit_comment       => '580c31928bc9567075169cacf3e5a03c92514b81',
    #   :issue_two_comment2   => '0407a96aebf2108e60927545f054a02f20e981ac',
    #   :issue_three_comment2 => '0407a96aebf2108e60927545f054a02f20e981ac',
    #   :issue_three_comment1 => 'feff7babf81ab6dae82e2036fe457f0347d74c4f',
    #   :issue_two   => '11361c0dbe9a65c223ff07f084cceb9c6cf3a043',
    #   :issue_one   => '3a2662fad86206d8562adbf551855c01f248d4a2',
    #   :issue_three => 'dfe0ffed95402aed8420df921852edf6fcba2966',
    #   :page_one => '703c947591298f9ef248544c67656e966c03600f',
    #   :page_two => 'db02e0759364942f7c06d0386566101d5dc9343d'
    # }.each_pair do |key, sha|
    #   define_method(key) { sha }
    # end
    
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

