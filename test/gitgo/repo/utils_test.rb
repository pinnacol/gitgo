require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/repo/utils'

class RepoUtilsTest < Test::Unit::TestCase
  include Gitgo::Repo::Utils
  
  #
  # Repo#ancestry test
  #
  
  def render(tree, lines=[], indent="")
    lines << "#{indent}<ul>"

    tree.each do |branch|
      if branch.kind_of?(Array)
        lines << "#{indent}<li>"
        render(branch, lines, indent + "  ")
        lines << "#{indent}</li>"
      else
        lines << "#{indent}<li>#{branch}</li>"
      end
    end

    lines << "#{indent}</ul>"
    lines
  end

  def test_ancestry_documentation_in_document
    ancestry = {
      "a" => ["b"],
      "b" => ["c", "d"],
      "c" => [],
      "d" => ["e"],
      "e" => []
    }
  
    ancestry_for_a = flatten(ancestry)['a']
    tree = collapse(ancestry_for_a)
    assert_equal ["a", "b", ["c"], ["d", "e"]], tree
    
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
    assert_equal expected, "\n" + render(tree).join("\n") + "\n"
  end
  
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
end