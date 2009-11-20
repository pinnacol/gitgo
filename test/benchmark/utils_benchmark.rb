require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo/utils'
require 'benchmark'

class UtilsBenchmark < Test::Unit::TestCase
  include Gitgo::Repo::Utils
  acts_as_subset_test
  
  def test_flatten_speed
    benchmark_test do |x|
      n = 10000
      
      x.report("flatten (one)") do
        n.times do 
          one = {
            "a" => ["b"],
            "b" => ["c"],
            "c" => ["d"],
            "d" => ["e"],
            "e" => []
          }
          flatten(one)
        end
      end
      
      x.report("flatten (two)") do
        n.times do 
          two = {
            "a" => ["b"],
            "b" => ["c", "d"],
            "c" => ["d"],
            "d" => ["e"],
            "e" => []
          }
          flatten(two)
        end
      end
    end
  end
  
  def test_collapse_speed
    benchmark_test do |x|
      n = 100000
      
      one = ["a", ["b", ["c", ["d", ["e"]]]]]
      assert_equal ["a", "b", "c", "d", "e"], collapse(["a", ["b", ["c", ["d", ["e"]]]]])
      
      x.report("collapse (one)") do
        n.times { collapse(one) }
      end
      
      two = ["a", ["b", ["c", ["d", ["e"]]], ["d", ["e"]]]]
      assert_equal ["a", "b", ["c", "d", "e"], ["d", "e"]], collapse(["a", ["b", ["c", ["d", ["e"]]], ["d", ["e"]]]])
      
      x.report("collapse (two)") do
        n.times { collapse(two) }
      end
    end
  end
end
