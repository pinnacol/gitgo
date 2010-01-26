require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/helpers'

class HelpersTest < Test::Unit::TestCase
  include Gitgo::Helpers
  
  attr_reader :request
  
  def setup
    @request = Rack::Request.new({})
  end
  
  #
  # url test
  #
  
  def test_url_returns_path
    assert_equal "/", url("/")
    assert_equal "/path/to/resource", url("/path/to/resource")
  end
  
  def test_url_relative_to_mount_point
    request.env[Gitgo::MOUNT] = '/mount/point'
    
    assert_equal "/mount/point/", url("/")
    assert_equal "/mount/point/path/to/resource", url("/path/to/resource")
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
  # gformat test
  #
  
  def test_gformat_substitutes_shas_look_alikes_with_links
    str = "this sha: 19377b7ec7b83909b8827e52817c53a47db96cf0 is linked"
    assert_equal %Q{this sha: <a href="/obj/19377b7ec7b83909b8827e52817c53a47db96cf0">19377b7ec7b83909b8827e52817c53a47db96cf0</a> is linked}, gformat(str)
  end
  
  def test_gformat_does_not_substitute_non_sha_strings
    str = "not a sha: z9377b7ec7b83909b8827e52817c53a47db96cf0"
    assert_equal %Q{not a sha: z9377b7ec7b83909b8827e52817c53a47db96cf0}, gformat(str)
  end
end