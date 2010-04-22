require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/index'
require 'digest/sha1'

class IndexTest < Test::Unit::TestCase
  Index = Gitgo::Index
  acts_as_file_test
  
  attr_reader :index
  
  def setup
    super
    @index = Index.new method_root.path
  end
  
  def digest(str)
    Digest::SHA1.hexdigest(str)
  end
  
  def shas(*strs)
    strs.collect {|str| digest(str) }
  end
  
  def pack_ints(*ints)
    ints.pack('L*')
  end
  
  #
  # head test
  #
  
  def test_head_returns_the_sha_in_head_file_if_it_exists
    assert_equal nil, index.head
    
    sha = digest("commit")
    method_root.prepare(index.path(Index::HEAD)) {|io| io << sha }
    
    assert_equal sha, index.head
  end
  
  #
  # list test
  #
  
  def test_list_reads_the_list_file_into_an_array
    list = shas('a', 'b', 'c', 'd')
    method_root.prepare(index.path(Index::LIST)) do |io|
      io << [list.join].pack('H*')
    end
    
    assert_equal list, index.list
  end
  
  #
  # map test
  #
  
  def test_map_reads_the_map_file_into_a_hash
    method_root.prepare(index.path(Index::MAP)) do |io|
      io << pack_ints(1,2,3,4)
    end
    
    assert_equal({1 => 2, 3 => 4}, index.map)
  end
  
  #
  # path test
  #
  
  def test_path_returns_initial_path
    index = Index.new "/path"
    assert_equal "/path", index.path
  end
  
  def test_path_returns_segments_joined_to_path
    index = Index.new "/path"
    assert_equal "/path/key/value", index.path("key", "value")
  end
  
  #
  # idx test
  #
  
  def test_idx_returns_index_of_sha_in_list
    a, b, c = shas('a', 'b', 'c')
    index.list.concat [a, b, c]
    
    assert_equal 0, index.idx(a)
    assert_equal 1, index.idx(b)
    assert_equal 2, index.idx(c)
  end
  
  def test_idx_appends_sha_to_list_if_necessary
    a, b, c = shas('a', 'b', 'c')
    
    assert_equal [], index.list
    assert_equal 0, index.idx(a)
    assert_equal 1, index.idx(b)
    assert_equal 2, index.idx(c)
    assert_equal [a, b, c], index.list
  end
  
  #
  # graph_head_idx test
  #
  
  def test_graph_head_idx_returns_idx_if_idx_is_not_mapped
    assert_equal 0, index.graph_head_idx(0)
  end
  
  def test_graph_head_idx_returns_idx_if_idx_is_nil_in_map
    index.map[0] = nil
    assert_equal 0, index.graph_head_idx(0)
  end
  
  def test_graph_head_idx_returns_the_deconvoluted_graph_head_idx_as_specified_in_map
    index.map[1] = 0
    index.map[2] = 1
    
    assert_equal 0, index.graph_head_idx(1)
    assert_equal 0, index.graph_head_idx(2)
  end
  
  def test_graph_head_idx_raises_error_for_cyclic_graphs
    index.map[1] = 0
    index.map[2] = 1
    index.map[0] = 2
    
    err = assert_raises(RuntimeError) { index.graph_head_idx(1) }
    assert_equal 'cannot deconvolute cyclic graph: [1, 0, 2, 1]', err.message
  end
  
  #
  # AGET test
  #
  
  def test_AGET_returns_array_of_integers
    assert_equal [], index['key']['value']
    index['key']['value'] << 1
    assert_equal [1], index['key']['value']
  end
  
  def test_AGET_reads_from_filter_file_if_key_value_is_unpopulated
    method_root.prepare(index.path(Index::FILTER, 'key', 'value')) do |io|
      io << pack_ints(1,2,3)
    end
    
    assert_equal false, index['key'].has_key?('value')
    assert_equal([1,2,3], index['key']['value'])
  end
  
  #
  # join test
  #
  
  def test_join_returns_idx_for_specifed_values
    index['key']['one'] = [0, 1]
    index['key']['two'] = [2]
    
    assert_equal [0, 1], index.join('key', 'one').sort
    assert_equal [0, 1, 2], index.join('key', 'one', 'two').sort
  end
  
  #
  # select test
  #
  
  def test_select_returns_shas_matching_any_and_all_criteria
    index.list.concat shas('a', 'b', 'c')
    index['state']['open'] = [0, 2]
    index['state']['closed'] = [1]
    index['at']['one'] = [0, 1]
    index['at']['two'] = [2]
    
    assert_equal [0, 2], index.select(:all => {'state' => 'open'})
    assert_equal [0], index.select(:all => {'state' => 'open', 'at' => 'one'})
    
    assert_equal [0, 2], index.select(:any => {'state' => 'open'})
    assert_equal [0, 1, 2], index.select(:any => {'state' => 'open', 'at' => 'one'})
    
    assert_equal [0], index.select(:all => {'state' => 'open', 'at' => 'one'}, :any => {'at' => 'one'})
    assert_equal [], index.select(:all => {'state' => 'open', 'at' => 'one'}, :any => {'at' => 'two'})
    assert_equal [2], index.select(:all => {'state' => 'open'}, :any => {'at' => 'two'})
  end
  
  def test_select_allows_array_values
    index.list.concat shas('a', 'b')
    index['tags']['a'] = [0, 1]
    index['tags']['b'] = [0]
    index['tags']['c'] = [1]
    
    assert_equal [0], index.select(:all => {'tags' => ['a', 'b']})
    assert_equal [], index.select(:all => {'tags' => ['a', 'd']})
    assert_equal [0, 1], index.select(:any => {'tags' => ['b', 'c']})
  end
  
  def test_select_only_selects_among_specified_basis
    index.list.concat shas('a', 'b')
    index['state']['open'] = [0, 1]
    index['state']['closed'] = [2]
    
    assert_equal [0], index.select(:basis => [0, 2], :all => {'state' => 'open'})
    assert_equal [0, 1], index.select(:basis => [0, 1, 2], :all => {'state' => 'open'})
  end
  
  #
  # write test
  #
  
  def test_write_writes_sha_to_head_file
    a = digest('a')
    index.write(a)
    
    assert_equal a, File.read(index.head_file)
  end
  
  def test_write_writes_list_to_list_file
    a, b = shas('a', 'b')
    index.list << a
    index.list << b
    index.write
    
    assert_equal [[a,b].join].pack("H*"), File.read(index.list_file)
  end
  
  def test_write_writes_map_to_map_file
    index.map[1] = 2
    index.write
    
    assert_equal pack_ints(1, 2), File.read(index.map_file)
  end
  
  def test_write_writes_cache_to_respective_index_files
    a, b, c = shas('a', 'b', 'c')
    index['state']['open'] = [0, 2]
    index['state']['closed'] = [1]
    index.write
    
    assert_equal pack_ints(0, 2), File.read(index.path(Index::FILTER, 'state', 'open'))
    assert_equal pack_ints(1), File.read(index.path(Index::FILTER, 'state', 'closed'))
  end
  
  #
  # compact test
  #
  
  def test_compact_removes_duplicates_from_list
    a, b, c = shas('a', 'b', 'c')
    index.list.concat [a, b, b, c, a]
    
    index.compact
    assert_equal [a, b, c], index.list
  end
  
  def test_compact_updates_and_deconvolutes_mapped_idxs_to_new_idx_values
    a, b, c = shas('a', 'b', 'c')
    index.list.concat [a, b, b, c, a]
    
    index.map[0] = nil
    index.map[1] = 0   # b -> a
    index.map[2] = 0   # b -> a
    index.map[3] = 2   # c -> b
    index.map[4] = nil
    
    index.compact
    assert_equal({
      0 => nil,
      1 => 0,
      2 => 0
    }, index.map)
  end
  
  def test_compact_updates_filter_idx_values
    a, b, c = shas('a', 'b', 'c')
    index.list.concat [a, b, b, c, a]
    
    index['key']['value'] = [0, 3, 4]
    
    index.compact
    assert_equal [0, 2], index['key']['value']
  end
  
  #
  # reset test
  #
  
  def test_reset_clears_list
    index.list << 'a'
    index.reset
    assert_equal([], index.list)
  end
  
  def test_reset_clears_map
    index.map[1] = 2
    index.reset
    assert_equal({}, index.map)
  end
  
  def test_reset_clears_the_cache
    index.cache['a'] = {}
    index.reset
    assert_equal({}, index.cache)
  end
  
  #
  # clear test
  #
  
  def test_clear_clears_the_index_dir
    a = method_root.prepare("file.txt") {|io| io << "a" }
    b = method_root.prepare("dir/file.txt") {|io| io << "b" }
    
    assert_equal [a, b].sort, Dir.glob(index.path("**/*.txt")).sort
    index.clear
    assert_equal [], Dir.glob(index.path("**/*.txt"))
  end
end