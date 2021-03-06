require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/repo'

class GraphTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  
  attr_accessor :repo
  
  def setup
    super
    @repo = Repo.new(Repo::PATH => method_root.path(:repo))
  end
  
  def shas(*contents)
    contents.collect do |content|
      repo.save("content" => content)
    end
  end
  
  def assert_nodes_equal(expected, actual)
    assert_equal expected.sort, actual.sort
  end

  def assert_graph_equal(expected, actual)
    assert_equal normalize(expected), normalize(actual)
  end
  
  def normalize(graph)
    hash = {}
    graph.each_pair do |key, values|
      values.collect! {|value| content(value) }
      values.sort!
      hash[content(key)] = values
    end
    hash
  end

  def content(sha)
    sha ? repo.read(sha)['content'] : nil
  end
  
  #
  # original test
  #
  
  def test_original_returns_original_version_of_the_node
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    graph = repo.graph(a)
    assert_equal a, graph[a].original
    assert_equal a, graph[b].original
    assert_equal a, graph[c].original
  end
  
  #
  # versions test
  #
  
  def test_versions_returns_current_versions_of_the_node
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    graph = repo.graph(a)
    assert_nodes_equal [b, d], graph[a].versions
    assert_nodes_equal [d], graph[c].versions
    assert_nodes_equal [d], graph[d].versions
  end
  
  #
  # parents test
  #
  
  def test_parents_returns_deconvoluted_parents_of_the_node
    a, b, c, d, e = shas('a', 'b', 'c', 'd', 'e')
    repo.link(a, b)
    repo.link(b, d)
    repo.link(a, c)
    repo.link(c, e)
    repo.update(d, e)
    
    graph = repo.graph(a)
    assert_nodes_equal [],  graph[a].parents
    assert_nodes_equal [a], graph[b].parents
    assert_nodes_equal [a], graph[c].parents
    assert_nodes_equal [],  graph[d].parents
    assert_nodes_equal [b, c], graph[e].parents
  end
  
  #
  # children test
  #
  
  def test_children_returns_deconvoluted_children_of_the_node
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.link(a, c)
    repo.link(b, d)
    
    graph = repo.graph(a)
    assert_nodes_equal [],     graph[a].children
    assert_nodes_equal [c, d], graph[b].children
    assert_nodes_equal [],     graph[c].children
  end
  
  #
  # tails test
  #
  
  def tails_returns_all_tails_in_the_graph
    a, b, c, d, e = shas('a', 'b', 'c', 'd', 'e')
    repo.update(a, b)
    repo.link(a, c)
    repo.link(c, d)
    repo.link(a, e)
    
    graph = repo.graph(a)
    assert_equal [d, e].sort, graph.tails.sort
  end
  
  #
  # current? test
  #
  
  def test_current_check_returns_true_if_node_has_no_updates
    a, b, c = shas('a', 'b', 'c')
    repo.update(a, b)
    repo.link(a, c)
    
    graph = repo.graph(a)
    assert_equal false, graph[a].current?
    assert_equal true,  graph[b].current?
    assert_equal true,  graph[c].current?
  end
  
  #
  # tail? test
  #
  
  def test_tail_check_returns_true_if_node_has_no_children
    a, b, c = shas('a', 'b', 'c')
    repo.update(a, b)
    repo.link(a, c)
    
    graph = repo.graph(a)
    assert_equal false, graph[a].tail?
    assert_equal false, graph[b].tail?
    assert_equal true,  graph[c].tail?
  end
  
  #
  # links test
  #
  
  def test_links_returns_an_mapping_of_node_child_linkages
    a, b, c = shas('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)

    expected = {
      nil => [a],
      a => [b], 
      b => [c], 
      c => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end
  
  def test_links_allows_forks
    a, b, c = shas('a', 'b', 'c')
    repo.link(a, b)
    repo.link(a, c)

    expected = {
      nil => [a],
      a => [b, c], 
      b => [], 
      c => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end

  def test_links_allows_merges
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.link(a, b).link(b, d)
    repo.link(a, c).link(c, d)

    expected = {
      nil => [a],
      a => [b, c].sort,
      b => [d],
      c => [d],
      d => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end
  
  def test_links_deconvolutes_updates
    a, b, c, d, m, n, x, y = shas('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, d)
    repo.update(a, x).link(x, y)
    repo.update(b, m).link(m, n)

    expected = {
      nil => [x],
      c => [d],
      d => [],
      x => [y, m],
      y => [],
      m => [n, c],
      n => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end
  
  def test_links_removes_deletes
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, d)
    repo.delete(c)

    expected = {
      nil => [a],
      a => [b], 
      b => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end
  
  def test_links_removes_deletes_from_update
    a, b, c, x, y, z = shas('a', 'b', 'c', 'x', 'y', 'z')
    repo.link(a, b)
    repo.link(b, c)
    repo.update(b, x)
    repo.update(b, y)
    repo.update(x, z)
    repo.delete(x)

    expected = {
      nil => [a],
      a => [y], 
      y => [c],
      c => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end

  def test_links_with_multiple_heads
    a, b, m, n, x, y = shas('a', 'b', 'm', 'n', 'x', 'y')
    repo.link(a, b).update(a, m).update(a, x)
    repo.link(m, n)
    repo.link(x, y)

    expected = {
      nil => [m, x],
      b => [],
      x => [y, b],
      y => [],
      m => [n, b],
      n => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end

  def test_links_with_merged_lineages
    a, b, c, d, m, n, x, y = shas('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y')
    repo.link(a, b).link(a, x)
    repo.link(b, c)

    repo.link(x, y)

    repo.update(b, m).link(m, n)
    repo.link(x, m)

    expected = {
      nil => [a],
      a => [m, x],
      c => [],
      m => [n, c],
      n => [],
      x => [m, y],
      y => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end

  def test_links_with_merged_lineages_and_multiple_updates
    a, b, c, d, m, n, x, y, p, q = shas('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y', 'p', 'q')
    repo.link(a, b).link(a, x)
    repo.link(b, c)

    repo.link(x, y)
    repo.link(p, q)

    repo.update(b, m).link(m, n)
    repo.link(x, m)
    repo.update(m, p)

    expected = {
      nil => [a],
      a => [p, x],
      c => [],
      n => [],
      x => [p, y],
      y => [],
      p => [c, n, q],
      q => []
    }

    assert_graph_equal expected, repo.graph(a).links
  end
  
  def test_links_detects_circular_linkage
    a, b, c = shas('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, a)

    err = assert_raises(RuntimeError) { repo.graph(a).links }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{c}
  #{a}
}, err.message
  end

  def test_links_detects_circular_linkage_with_replacement
    a, b, c = shas('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    repo.link(b, a)

    err = assert_raises(RuntimeError) { repo.graph(a).links }
    assert_equal %Q{circular link detected:
  #{a}
  #{c}
  #{a}
}, err.message
  end

  def test_links_detects_circular_linkage_through_replacement
    a, b, c = shas('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    repo.link(c, a)

    err = assert_raises(RuntimeError) { repo.graph(a).links }
    assert_equal %Q{circular link detected:
  #{a}
  #{c}
  #{a}
}, err.message
  end
  
  def test_links_detects_circular_linkage_causes_by_replacement
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.link(a, b)
    repo.link(b, c)
    
    repo.link(a, c)
    repo.link(c, d)
    
    repo.update(b, d)
    
    err = assert_raises(RuntimeError) { repo.graph(a).links }
    expected = [
%Q{circular link detected:
  #{a}
  #{c}
  #{d}
  #{c}
}, 
%Q{circular link detected:
  #{a}
  #{d}
  #{c}
  #{d}
}]
    assert_equal true, expected.include?(err.message)
  end
  
  def test_links_returns_empty_hash_when_head_is_nil
    graph = repo.graph(nil)
    assert_equal({}, graph.links)
  end
  
  #
  # graph test
  #
  
  def test_graph_for_single_line
    a, b, c = shas('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)
    
    assert_equal [
      [nil, 0, 0, [], [0]], 
      [a, 0, 1, [], [0]], 
      [b, 0, 2, [], [0]], 
      [c, 0, 3, [0], []]
    ], repo.graph(a).collect
  end
  
  def test_graph_for_fork
    a, b, c, d = shas('a', 'b', 'c', 'd').sort
    repo.link(a, b)
    repo.link(a, c)
    repo.link(a, d)
    
    assert_equal [
      [nil, 0, 0, [], [0]], 
      [a, 0, 1, [], [0,1,2]], 
      [b, 0, 2, [0,1,2], []], 
      [c, 1, 3, [0,1,2], []],
      [d, 2, 4, [0,1,2], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_fork_and_merge
    a, b, c, d = shas('a', 'b', 'c', 'd').sort
    repo.link(a, b)
    repo.link(a, c)
    repo.link(b, d)
    repo.link(c, d)
    
    assert_equal [
      [nil, 0, 0, [], [0]],
      [a, 0, 1, [], [0,1]],
      [b, 0, 2, [1], [0]],
      [c, 1, 3, [0], [0]],
      [d, 0, 4, [0], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_fork_with_partial_merge
    a, b, c, d, e = shas('a', 'b', 'c', 'd', 'e').sort
    repo.link(a, b)
    repo.link(a, c)
    repo.link(a, d)
    
    repo.link(b, e)
    repo.link(d, e)
    
    assert_equal [
      [nil, 0, 0, [], [0]],
      [a, 0, 1, [], [0,1,2]],
      [b, 0, 2, [1,2], [0]],
      [c, 1, 3, [0,1,2], []],
      [d, 2, 4, [0,1], [0]],
      [e, 0, 5, [0,1], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_multiple_merge_inward
    a, b, c, d, e = shas('a', 'b', 'c', 'd', 'e').sort
    repo.link(a, b)
    repo.link(a, c)
    
    repo.link(b, e)
    
    repo.link(c, d)
    repo.link(c, e)
    
    repo.link(d, e)
    
    assert_equal [
      [nil, 0, 0, [], [0]],
      [a, 0, 1, [], [0,1]],
      [b, 0, 2, [1], [0]],
      [c, 1, 3, [0], [1,0]],
      [d, 1, 4, [0], [0]],
      [e, 0, 5, [0], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_multiple_merge_outward
    a, b, c, d, e, f, g = shas('a', 'b', 'c', 'd', 'e', 'f', 'g').sort
    repo.link(a, b)
    repo.link(a, c)
    
    repo.link(b, g)
    
    repo.link(c, d)
    repo.link(c, f)
    
    repo.link(d, e)
    repo.link(e, f)
    repo.link(f, g)

    assert_equal [
      [nil, 0, 0, [], [0]],
      [a, 0, 1, [], [0, 1]],
      [b, 0, 2, [1], [0]],
      [c, 1, 3, [0], [1, 2]],
      [d, 1, 4, [0, 2], [1]],
      [e, 1, 5, [0, 2], [2]],
      [f, 2, 6, [0], [0]],
      [g, 0, 7, [0], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_fork_merge_refork
    a, b, c, d, e, f, g, h, i = shas('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i').sort
    repo.link(a, b)
    repo.link(a, c)
    repo.link(a, d)
    repo.link(b, e)
    repo.link(d, e)
    repo.link(e, f)
    repo.link(e, i)
    repo.link(f, g)
    repo.link(f, h)
    
    assert_equal [
      [nil, 0, 0, [], [0]],
      [a, 0, 1, [], [0,1,2]],
      [b, 0, 2, [1,2], [0]],
      [c, 1, 3, [0,1,2], []],
      [d, 2, 4, [0,1], [0]],
      [e, 0, 5, [1], [0,2]],
      [f, 0, 6, [1,2], [0,3]],
      [g, 0, 7, [0,1,2,3], []],
      [h, 3, 8, [0,1,2,3], []],
      [i, 2, 9, [0,1,2,3], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_merge_and_fork_on_separate_branches
    a, b, c, d, e, f, g = shas('a', 'b', 'c', 'd', 'e', 'f', 'g').sort
    repo.link(a, b)
    repo.link(a, c)
    repo.link(a, e)
    repo.link(b, d)
    repo.link(c, d)
    repo.link(e, f)
    repo.link(e, g)

    assert_equal [
      [nil, 0, 0, [], [0]],
      [a, 0, 1, [], [0,1,2]],
      [b, 0, 2, [1,2], [0]],
      [c, 1, 3, [0,2], [0]],
      [d, 0, 4, [0,2], []],
      [e, 2, 5, [0], [1, 2]],
      [f, 1, 6, [0,1,2], []],
      [g, 2, 7, [0,1,2], []]
    ], repo.graph(a).sort.collect
  end
  
  def test_graph_for_multiple_heads
    a, b, c = shas('a', 'b', 'c').sort
    repo.update(a, b)
    repo.update(a, c)
    
    assert_equal [
      [nil, 0, 0, [], [0,1]], 
      [b, 0, 1, [0,1], []], 
      [c, 1, 2, [0,1], []]
    ], repo.graph(a).sort.collect
  end
  
  #
  # draw test
  #
  
  def test_draw_for_merge_and_fork_on_separate_branches
    a, b, c, d, e, f, g = shas('a', 'b', 'c', 'd', 'e', 'f', 'g').sort
    repo.link(a, b)
    repo.link(a, c)
    repo.link(a, e)
    repo.link(b, d)
    repo.link(c, d)
    repo.link(e, f)
    repo.link(e, g)
    
    expected = %q{
*
|---+
* | |
| | |
| * |
|-+ |
*   |
|   |
|   *
| +-|
| * |
| | |
| | *
| | |
}.strip
     
     assert_equal expected, repo.graph(a).draw
  end
end