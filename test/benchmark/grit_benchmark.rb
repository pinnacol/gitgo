require File.dirname(__FILE__) + "/../test_helper"
require 'grit'

class GritBenchmark < Test::Unit::TestCase
  include RepoTestHelper
  acts_as_subset_test
  
  attr_reader :repo
  
  def setup
    super
    @repo = Grit::Repo.new setup_repo('simple.git')
  end
  
  def test_cat_file_vs_get_obj_by_sha
    benchmark_test do |x|
      n = 1000
      sha = 'c9036dc2e34776218519a95470bd1dce1b47ac9a'
      
      cmd = "GIT_DIR='#{repo.path}' git cat-file blob #{sha}"
      x.report("cat_file") do
        n.times do
          IO.popen(cmd, 'r') {|io| io.read }
        end
      end
      
      ruby_git = repo.git.ruby_git
      x.report("grit") do
        n.times do
          ruby_git.get_raw_object_by_sha1(sha).content
        end
      end
      
      cat_content = IO.popen(cmd, 'r') {|io| io.read }
      grit_content = ruby_git.get_raw_object_by_sha1(sha).content
      assert_equal cat_content, grit_content
    end
  end
end