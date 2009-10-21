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
      "11361c0dbe9a65c223ff07f084cceb9c6cf3a043",
      "3a2662fad86206d8562adbf551855c01f248d4a2",
      "dfe0ffed95402aed8420df921852edf6fcba2966"
    ], latest
  end
end