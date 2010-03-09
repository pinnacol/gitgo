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
  
  def create_nodes(*contents)
    date = Time.now
    contents.collect do |content|
      date += 1
      repo.store("content" => content, "date" => date)
    end
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
  # origin test
  #
  
  def test_original_returns_original_version_of_the_node
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    graph = repo.graph(a)
    assert_equal a, graph.original(a)
    assert_equal a, graph.original(b)
    assert_equal a, graph.original(d)
  end
  
  #
  # versions test
  #
  
  def test_versions_returns_current_versions_of_the_node
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    graph = repo.graph(a)
    assert_equal [b, d].sort, graph.versions(a).sort
    assert_equal [d], graph.versions(c)
    assert_equal [d], graph.versions(d)
  end
  
  #
  # parents test
  #
  
  def test_parents_returns_deconvoluted_parents_of_the_node
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.link(a, c)
    repo.link(b, d)
    
    graph = repo.graph(a)
    assert_equal [], graph.parents(a)
    assert_equal [], graph.parents(b)
    assert_equal [b], graph.parents(c)
    assert_equal [b], graph.parents(d)
  end
  
  #
  # children test
  #
  
  def test_children_returns_deconvoluted_children_of_the_node
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.link(a, c)
    repo.link(b, d)
    
    graph = repo.graph(a)
    assert_equal [c], graph.children(a)
    assert_equal [c, d].sort, graph.children(b).sort
    assert_equal [], graph.children(c)
  end
  
  #
  # current? test
  #
  
  def test_current_check_returns_true_if_node_has_no_updates
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.link(a, c)
    
    graph = repo.graph(a)
    assert_equal false, graph.current?(a)
    assert_equal true, graph.current?(b)
    assert_equal true, graph.current?(c)
  end
  
  #
  # tail? test
  #
  
  def test_tail_check_returns_true_if_node_has_no_children
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.link(a, c)
    
    graph = repo.graph(a)
    assert_equal false, graph.tail?(a)
    assert_equal false, graph.tail?(b)
    assert_equal true, graph.tail?(c)
  end
  
  #
  # tree test
  #
  
  def test_tree_returns_an_graph_of_shas
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)

    expected = {
      nil => [a],
      a => [b], 
      b => [c], 
      c => []
    }

    assert_graph_equal expected, repo.graph(a).tree
  end

  def test_tree_allows_merge_linkages
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.link(a, b).link(b, d)
    repo.link(a, c).link(c, d)

    expected = {
      nil => [a],
      a => [b, c].sort,
      b => [d],
      c => [d],
      d => []
    }

    assert_graph_equal expected, repo.graph(a).tree
  end

  def test_tree_deconvolutes_updates
    a, b, c, d, m, n, x, y = create_nodes('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y')
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

    assert_graph_equal expected, repo.graph(a).tree
  end

  def test_tree_with_multiple_heads
    a, b, m, n, x, y = create_nodes('a', 'b', 'm', 'n', 'x', 'y')
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

    assert_graph_equal expected, repo.graph(a).tree
  end

  def test_tree_with_merged_lineages
    a, b, c, d, m, n, x, y = create_nodes('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y')
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

    assert_graph_equal expected, repo.graph(a).tree
  end

  def test_tree_with_merged_lineages_and_multiple_updates
    a, b, c, d, m, n, x, y, p, q = create_nodes('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y', 'p', 'q')
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

    assert_graph_equal expected, repo.graph(a).tree
  end
  
  def test_tree_detects_circular_linkage
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, a)

    err = assert_raises(RuntimeError) { repo.graph(a).tree }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{c}
  #{a}
}, err.message
  end

  def test_tree_detects_circular_linkage_with_replacement
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    repo.link(b, a)

    err = assert_raises(RuntimeError) { repo.graph(a).tree }
    assert_equal %Q{circular link detected:
  #{a}
  #{c}
  #{a}
}, err.message
  end

  def test_tree_detects_circular_linkage_through_replacement
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    repo.link(c, a)

    err = assert_raises(RuntimeError) { repo.graph(a).tree }
    assert_equal %Q{circular link detected:
  #{a}
  #{c}
  #{a}
}, err.message
  end
  
  def test_tree_detects_circular_linkage_causes_by_replacement
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.link(a, b)
    repo.link(b, c)
    
    repo.link(a, c)
    repo.link(c, d)
    
    repo.update(b, d)
    
    err = assert_raises(RuntimeError) { repo.graph(a).tree }
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
  
  def test_tree_returns_empty_hash_when_head_is_nil
    graph = repo.graph(nil)
    assert_equal({}, graph.tree)
  end
end