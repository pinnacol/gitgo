require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/helper/utils'

class HelperUtilsTest < Test::Unit::TestCase
  include Gitgo::Helper::Utils
  
  #
  # flatten test
  #
  
  def test_flatten_documentation
    ancestry = {
      "a" => ["b"],
      "b" => ["c", "d"],
      "c" => [],
      "d" => ["e"],
      "e" => []
    }

    expected = {
      "a" => ["a", ["b", ["c"], ["d", ["e"]]]],
      "b" => ["b", ["c"], ["d", ["e"]]],
      "c" => ["c"],
      "d" => ["d", ["e"]],
      "e" => ["e"]
    }
    assert_equal expected, flatten(ancestry)
  end
  
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
  
  def test_collapse_documentation
    assert_equal ["a", "b", "c"], collapse(["a", ["b", ["c"]]])
    assert_equal ["a", "b", ["c"], ["d", "e"]], collapse(["a", ["b", ["c"], ["d", ["e"]]]])
  end
  
  def test_collapse_collapses_single_decendents_into_parent
    assert_equal ["a", "b", "c", "d", "e"], collapse(["a", ["b", ["c", ["d", ["e"]]]]])
    assert_equal ["a", "b", ["c", "d", "e"], ["d", "e"]], collapse(["a", ["b", ["c", ["d", ["e"]]], ["d", ["e"]]]])
    assert_equal ["a", ["b", "e"], ["c", "e"], ["d", "e"]], collapse(["a", ["b", ["e"]], ["c", ["e"]], ["d", ["e"]]])
  end
  
  #
  # render test
  #

  def test_render_renders_flattened_collapsed_list_of_nodes
    list = ["a", "b", ["c"], ["d", "e"]]
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

    assert_equal expected, "\n" + render(list).join + "\n"
  end
  
  #
  # nodes test
  #
  
  def test_nodes_for_single_line
    tree = {
      nil => [0],
      0 => [1],
      1 => [2],
      2 => []
    }
    
    assert_equal [
      [nil, 0, [], [0]], 
      [0, 0, [], [0]], 
      [1, 0, [], [0]], 
      [2, 0, [], []]
    ], nodes(tree)
  end
  
  def test_nodes_for_fork
    tree = {
      nil => [0],
      0 => [1,2,3],
      1 => [],
      2 => [],
      3 => []
    }
    
    assert_equal [
      [nil, 0, [], [0]], 
      [0, 0, [], [0,1,2]], 
      [1, 0, [1,2], []], 
      [2, 1, [2], []],
      [3, 2, [], []]
    ], nodes(tree)
  end
  
  def test_nodes_for_fork_with_partial_merge
    tree = {
      nil => [0],
      0 => [1,2,3],
      1 => [4],
      2 => [],
      3 => [4],
      4 => []
    }
    
    assert_equal [
      [nil, 0, [], [0]],
      [0, 0, [], [0, 1, 2]],
      [1, 0, [1, 2], [0]],
      [2, 1, [0, 2], []],
      [3, 2, [0], [0]],
      [4, 0, [], []]
    ], nodes(tree)
  end
  
  def test_nodes_for_multiple_fork_points
    tree = {
      nil => [0],
      0 => [1,2],
      1 => [4],
      2 => [3,4],
      3 => [4],
      4 => []
    }
    
    assert_equal [
      [nil, 0, [], [0]],
      [0, 0, [], [0, 1]],
      [1, 0, [1], [0]],
      [2, 1, [0], [1, 0]],
      [3, 1, [], [0]],
      [4, 0, [], []]
    ], nodes(tree)
  end
  
  def test_nodes_for_multiple_merge_points
    tree = {
      nil => [0],
      0 => [1,2],
      1 => [6],
      2 => [3,5],
      3 => [4],
      4 => [5],
      5 => [6],
      6 => []
    }
    
    assert_equal [
      [nil, 0, [], [0]],
      [0, 0, [], [0, 1]],
      [1, 0, [1], [0]],
      [2, 1, [0], [1, 2]],
      [3, 1, [0, 2], [1]],
      [4, 1, [0, 2], [2]],
      [5, 2, [0], [0]],
      [6, 0, [], []]
    ], nodes(tree)
  end
  
  def test_nodes_for_fork_merge_refork
    tree = {
      nil => [0],
      0 => [1,2,3],
      1 => [4],
      2 => [],
      3 => [4],
      4 => [5,8],
      5 => [6,7],
      6 => [],
      7 => [],
      8 => []
    }
    
    assert_equal [
      [nil, 0, [], [0]],
      [0, 0, [], [0, 1, 2]],
      [1, 0, [1, 2], [0]],
      [2, 1, [0, 2], []],
      [3, 2, [0], [0]],
      [4, 0, [], [0, 2]],
      [5, 0, [2], [0, 3]],
      [6, 0, [2, 3], []],
      [7, 3, [2], []],
      [8, 2, [], []]
    ], nodes(tree)
  end
  
  def test_nodes_for_multiple_heads
    tree = {
      nil => [0,1,2],
      0 => [],
      1 => [],
      2 => []
    }
    
    assert_equal [
      [nil, 0, [], [0,1,2]], 
      [0, 0, [1,2], []], 
      [1, 1, [2], []], 
      [2, 2, [], []]
    ], nodes(tree)
  end
end