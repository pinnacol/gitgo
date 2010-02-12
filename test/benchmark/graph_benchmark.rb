require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/graph'
require 'benchmark'

class GraphBenchmark < Test::Unit::TestCase
  acts_as_subset_test
  acts_as_file_test
  
  Repo = Gitgo::Repo
  Graph = Gitgo::Graph
  
  attr_accessor :repo, :graph
  
  def setup
    super
    @repo = Repo.init method_root.path(:repo)
    @graph = Graph.new @repo
  end
  
  def create_docs(*contents)
    date = Time.now
    contents.collect do |content|
      date += 1
      repo.store("content" => content, "date" => date)
    end
  end
  
  def test_tree_for_simple_linkage
    benchmark_test do |bm|
      a, b, c, d, e, f, g = create_docs('a', 'b', 'c', 'd' , 'e', 'f', 'g')
      repo.link(a, b)
      repo.link(b, c)
      repo.link(c, d)
      repo.link(d, e)
      repo.link(e, f)
      repo.link(f, g)
    
      bm.report("1k (7 links)") do
        1000.times { graph.tree(a, true) }
      end
    end
  end
  
  def test_tree_for_merged_lineage_with_multiple_updates
    benchmark_test do |bm|
      a, b, c, d, m, n, x, y, p, q = create_docs('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y', 'p', 'q')
      repo.link(a, b).link(a, x)
      repo.link(b, c)

      repo.link(x, y)
      repo.link(p, q)

      repo.update(b, m).link(m, n)
      repo.link(x, m)
      repo.update(m, p)
    
      bm.report("1k") do
        1000.times { graph.tree(a, true) }
      end
    end
  end
end