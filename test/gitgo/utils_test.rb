require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/utils'

class UtilsTest < Test::Unit::TestCase
  include Gitgo::Utils

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
  
end