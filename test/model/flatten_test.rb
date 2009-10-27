require File.dirname(__FILE__) + "/../test_helper"

class FlattenTest < Test::Unit::TestCase
  
  def ancestors(child, ancestry, generation=0)
    all = []
    parents = ancestry[child]
    
    parents.each do |parent|
      all.concat ancestors(parent, ancestry, generation - 1)
    end if generation > 0
    
    all.concat parents
    all
  end
  
  def common_ancestor(children, parents)
    children = children.collect do |child|
      child.kind_of?(Array) ? child : [[], [child]]
    end
    
    ancestors = []
    found_new_ancestors = false
    
    children.collect! do |ancestry, last_gen|
      next_gen = []
      last_gen.each do |child|
        next unless new_ancestors = parents[child]
        
        found_new_ancestors = true
        ancestry.concat(new_ancestors)
        next_gen.concat(new_ancestors)
      end
      
      ancestors << ancestry
      [ancestry, next_gen]
    end
    
    all = ancestors.flatten
    common = ancestors.inject(all) {|a, b| a & b }
    common.first or (found_new_ancestors ? common_ancestor(children, parents) : nil)
  end
  
  def flatten(links)
    ancestry = {}
    links.each_pair do |parent, children|
      children.each do |child| 
        (ancestry[child] ||= []) << parent
      end
    end
    
    n = 0
    refs = links.dup
    ancestry.each_pair do |child, parents|
      next if parents.length <= 1
      
      ancestor = common_ancestor(parents, ancestry)
      
      links[ancestor] << n
      refs[n] = links[child]
      refs[child] = n
      
      n += 0
    end
    
    links.each_pair do |parent, children|
      if children.kind_of?(Array)
        children.collect! {|child| refs[child] }
        children.unshift(parent)
      end
    end
    
    refs.each_key do |parent|
      if parent.kind_of?(Integer)
        refs[parent].unshift(parent)
      end
    end
    
    heads = (links.keys - ancestry.keys)
    raise "multiple heads: #{heads.inspect}" if heads.length > 1
    links[heads[0]]
  end
  
  # a-b-c
  def test_flatten_single_thread
    set = {
      :a => [:b],
      :b => [:c],
      :c => []
    }
    
    assert_equal [:a, [:b, [:c]]], flatten(set)
  end
  
  # a-b
  #  -c
  def test_flatten_shallow_threads
    set = {
      :a => [:b, :c],
      :b => [],
      :c => []
    }
    
    assert_equal [:a, [:b], [:c]], flatten(set)
  end
  
  # a-b-c
  #  -d-e
  def test_flatten_threads
    set = {
      :a => [:b, :d],
      :b => [:c],
      :c => [],
      :d => [:e],
      :e => []
    }
    
    assert_equal [:a, [:b, [:c]], [:d, [:e]]], flatten(set)
  end
  
  # a-b-c-d
  #  -e-f-g
  def test_flatten_deep_threads
    set = {
      :a => [:b, :e],
      :b => [:c],
      :c => [:d],
      :d => [],
      :e => [:f],
      :f => [:g],
      :g => []
    }
    
    assert_equal [:a, [:b, [:c, [:d]]], [:e, [:f, [:g]]]], flatten(set)
  end
  
  # a-b
  #  -c-d-e
  def test_flatten_mixed_threads
    set = {
      :a => [:b, :c],
      :b => [],
      :c => [:d],
      :d => [:e],
      :e => []
    }
    
    assert_equal [:a, [:b], [:c, [:d, [:e]]]], flatten(set)
  end
  
  # a-b-c
  #  -d-c
  def test_merge_threads
    set = {
      :a => [:b, :d],
      :b => [:c],
      :c => [],
      :d => [:c]
    }
    
    assert_equal [:a, [:b, 0], [:d, 0], [0, :c]], flatten(set)
  end

  # a-b-c-e-f
  #  -d-c-e-f
  def test_merge_continuing_thread
    set = {
      :a => [:b, :d],
      :b => [:c],
      :c => [:e],
      :d => [:c],
      :e => [:f],
      :f => []
    }
    
    assert_equal [:a, [:b, 0], [:d, 0], [0, :c, [:e, [:f]]]], flatten(set)
  end


  # a-b-c
  #  -d-c
  #  -e
  def test_merged_mixed_threads
    set = {
      :a => [:b, :d, :e],
      :b => [:c],
      :c => [],
      :d => [:c],
      :e => []
    }
    
    assert_equal [:a, [:b, 0], [:d, 0], [0, :c], [:e]], flatten(set)
  end

  # a-b-c-e-f
  #  -d-c-e-f
  #  -g-h
  def test_merge_mixed_continuing_thread
    set = {
      :a => [:b, :d, :g],
      :b => [:c],
      :c => [:e],
      :d => [:c],
      :e => [:f],
      :f => [],
      :g => [:h],
      :h => []
    }
    
    assert_equal [:a, [:b, 0], [:d, 0], [0, :c, [:e, [:f]]], [:g, [:h]]], flatten(set)
  end

  # a-b-c-d-e
  #    -f-g-e
  #  -h-i
  def test_merge_on_a_thread
    set = {
      :a => [:b, :h],
      :b => [:c, :f],
      :c => [:d],
      :d => [:e],
      :e => [],
      :f => [:g],
      :g => [:e],
      :h => [:i],
      :i => []
    }
    
    assert_equal [:a, [:b, [:c, [:d, 0]], [:f, [:g, 0]], [0, :e]], [:h, [:i]]], flatten(set)
  end

  # a-b-c-d-e-f-g
  #    -h-e-f-g
  #  -i-e-f-g
  def test_multiple_merge
    set = {
      :a => [:b, :i],
      :b => [:c, :h],
      :c => [:d],
      :d => [:e],
      :e => [:f],
      :f => [:g],
      :g => [],
      :h => [:e],
      :i => [:e]
    }
    
    assert_equal [:a, [:b, [:c, [:d, 0]], [:h, 0]], [:i, 0], [0, :e, [:f, [:g]]]], flatten(set)
  end

  # a-b-c-d-e
  #  -f-c-d-e
  #  -g-d-e
  def test_in_and_out_merge
    set = {
      :a => [:b, :f, :g],
      :b => [:c],
      :c => [:d],
      :d => [:e],
      :e => [],
      :f => [:c],
      :g => [:d]
    }
    
    assert_equal [:a, [:b, 0], [:f, 0], [0, :c, 1], [:g, 1], [1, :d, [:e]]], flatten(set)
  end
end