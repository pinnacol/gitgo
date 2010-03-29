require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/helper/format'

class FormatTest < Test::Unit::TestCase
  Format = Gitgo::Helper::Format
  
  class MockController
    def url(*path)
      File.join("/", *path)
    end
  end
  
  attr_reader :format
  
  def setup
    @format = Format.new MockController.new
  end
  
  #
  # text test
  #
  
  def test_text_substitutes_sha_look_alikes_with_obj_links
    str = "this sha: 19377b7ec7b83909b8827e52817c53a47db96cf0 is linked"
    assert format.text(str) =~ /<a.*>19377b7ec7b83909b8827e52817c53a47db96cf0<\/a>/
  end
  
  def test_text_does_not_substitute_non_sha_strings
    str = "not a sha: z9377b7ec7b83909b8827e52817c53a47db96cf0"
    assert_equal "not a sha: z9377b7ec7b83909b8827e52817c53a47db96cf0", format.text(str)
  end
  
  #
  # each_path test
  #
  
  def test_each_path_yields_links_to_each_path_segment
    results = []
    format.each_path("id", "path/to/obj") {|link| results << link }
    
    assert_equal [
      "<a href=\"/tree/id\">id</a>",
      "<a href=\"/tree/id/path\">path</a>",
      "<a href=\"/tree/id/path/to\">to</a>",
      "obj"
    ], results
    
    #
    results = []
    format.each_path("id", "") {|link| results << link }
    
    assert_equal [
      "<a href=\"/tree/id\">id</a>"
    ], results
  end
  
  #
  # tree test
  #

  def test_tree_renders_hash_as_list
    hash = {
      nil => ["a"],
      "a" => ["b"],
      "b" => ["c", "d"],
      "c" => [],
      "d" => ["e"],
      "e" => []
    }

    expected = %q{
<ul>
<li>a</li>
<li>b</li>
<li>
  <ul>
  <li>c</li>
  </ul>
</li>
<li>
  <ul>
  <li>d</li>
  <li>e</li>
  </ul>
</li>
</ul>
}

    assert_equal expected, "\n" + format.tree(hash).join + "\n"
  end
  
  def test_tree_renders_each_item_using_block
    hash = {
      nil => ["a"],
      "a" => ["b"],
      "b" => []
    }

    expected = %q{
<ul>
<li>A</li>
<li>B</li>
</ul>
}
    
    output = format.tree(hash) {|item| item.upcase }
    assert_equal expected, "\n" + output.join + "\n"
  end
  
  def test_tree_renders_into_and_returns_io_if_specified
    hash = {
      nil => ["a"],
      "a" => ["b"],
      "b" => []
    }

    expected = %q{
<ul>
<li>a</li>
<li>b</li>
</ul>
}

    io = ""
    assert_equal io, format.tree(hash, io)
    assert_equal expected, "\n" + io + "\n"
  end
    
  def test_tree_is_non_destructive_to_hash
    hash = {
      nil => ["a"],
      "a" => ["b"],
      "b" => []
    }

    format.tree(hash)

    assert_equal({
      nil => ["a"],
      "a" => ["b"],
      "b" => []
    }, hash)
  end
  
  #
  # tree! test
  #

  def test_tree_bang_is_destructive_to_hash
    hash = {
      nil => ["a"],
      "a" => ["b"],
      "b" => []
    }

    format.tree!(hash)

    assert_equal({
      nil => [nil, ["a", ["b"]]],
      "a" => ["a", ["b"]],
      "b" => ["b"]
    }, hash)
  end
end