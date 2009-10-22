require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/utils'

class UtilsTest < Test::Unit::TestCase
  include Gitgo::Utils
  include RepoTestHelper
  
  attr_accessor :repo
  
  def setup_repo(repo)
    @repo = Gitgo::Repo.new super(repo)
  end
  
  #
  # path_links test
  #
  
  def test_path_links
    assert_equal [
      "<a href=\"/tree/id\">id</a>",
      "<a href=\"/tree/id/path\">path</a>",
      "<a href=\"/tree/id/path/to\">to</a>",
      "obj"
    ], path_links("id", "path/to/obj")
    
    assert_equal [
      "<a href=\"/tree/id\">id</a>"
    ], path_links("id", "")
  end
  
  #
  # latest test
  #
  
  def test_latest_returns_the_latest_shas
    setup_repo('gitgo.git')
    
    assert_equal [
      issue_two,
      issue_one,
      issue_three
    ], latest
  end
  
  def test_latest_returns_empty_array_if_no_shas_are_dated
    setup_repo('simple.git')
    
    assert_equal [], latest
  end
end