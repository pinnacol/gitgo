require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/repo/utils'

class RepoUtilsTest < Test::Unit::TestCase
  include Gitgo::Repo::Utils
  
  #
  # flatten test
  #
  
  def test_flatten_flattens_an_ancestry
    hash = {
      "a" => ["b"],
      "b" => ["c"],
      "c" => ["d"],
      "d" => ["e"],
      "e" => []
    }
    
    assert_equal({
      "a" => ["a", ["b", ["c", ["d", ["e"]]]]],
      "b" => ["b", ["c", ["d", ["e"]]]],
      "c" => ["c", ["d", ["e"]]],
      "d" => ["d", ["e"]],
      "e" => ["e"]
    }, flatten(hash))
    
    hash = {
      "a" => ["b"],
      "b" => ["c", "d"],
      "c" => ["d"],
      "d" => ["e"],
      "e" => []
    }
    
    assert_equal({
      "a" => ["a", ["b", ["c", ["d", ["e"]]], ["d", ["e"]]]],
      "b" => ["b", ["c", ["d", ["e"]]], ["d", ["e"]]],
      "c" => ["c", ["d", ["e"]]],
      "d" => ["d", ["e"]],
      "e" => ["e"]
    }, flatten(hash))
  end
  
  def test_flatten_for_merge
    hash = {
      "a" => ["b", "c", "d"],
      "b" => ["e"],
      "c" => ["e"],
      "d" => ["e"],
      "e" => []
    }
    
    assert_equal({
      "a" => ["a", ["b", ["e"]], ["c", ["e"]], ["d", ["e"]]],
      "b" => ["b", ["e"]],
      "c" => ["c", ["e"]],
      "d" => ["d", ["e"]],
      "e" => ["e"]
    }, flatten(hash))
  end
  
  #
  # collapse test
  #
  
  def test_collapse_collapses_single_decendents_into_parent
    assert_equal ["a", "b", "c", "d", "e"], collapse(["a", ["b", ["c", ["d", ["e"]]]]])
    assert_equal ["a", "b", ["c", "d", "e"], ["d", "e"]], collapse(["a", ["b", ["c", ["d", ["e"]]], ["d", ["e"]]]])
    assert_equal ["a", ["b", "e"], ["c", "e"], ["d", "e"]], collapse(["a", ["b", ["e"]], ["c", ["e"]], ["d", ["e"]]])
  end
end