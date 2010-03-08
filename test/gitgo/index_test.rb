require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/index'
require 'digest/sha1'

class IndexTest < Test::Unit::TestCase
  Index = Gitgo::Index
  acts_as_file_test
  
  attr_reader :index
  
  def setup
    super
    @index = Index.new method_root.root
  end
  
  def digest(str)
    Digest::SHA1.hexdigest(str)
  end
  
  def shas(*strs)
    strs.collect {|str| digest(str) }
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
  # map test
  #
  
  def test_map_reads_the_map_file_into_an_array
    a, b, c, d = shas('a', 'b', 'c', 'd')
    method_root.prepare(index.path(Index::MAP)) do |io|
      io << [[a,b,c,d].join].pack('H*')
    end
    
    assert_equal({a => b, c => d}, index.map)
  end
  
  def test_map_respects_order_in_file
    a, b, c = shas('a', 'b', 'c')
    method_root.prepare(index.path(Index::MAP)) do |io|
      io << [[a,b,a,c].join].pack('H*')
    end
    
    assert_equal({a => c}, index.map)
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
  # AGET test
  #
  
  def test_AGET_returns_array_of_shas
    assert_equal [], index.cache['key']['value']
    
    a = digest('a')
    index.cache['key']['value'] << a
    
    assert_equal [a], index.cache['key']['value']
  end
  
  #
  # add test
  #
  
  def test_add_sets_sha_to_key_value_pair
    a = digest('a')
    index.add('key', 'value', a)
    assert_equal [a], index.cache['key']['value']
  end
  
  #
  # rm test
  #
  
  def test_rm_unsets_sha_to_key_value_pair
    a = digest('a')
    index.add('key', 'value', a)
    assert_equal [a], index.cache['key']['value']
    
    index.rm('key', 'value', a)
    assert_equal [], index.cache['key']['value']
  end
  
  def test_unset_silently_does_nothing_if_the_sha_is_not_set_for_key_value_pair
    a = digest('a')
    assert_equal [], index.cache['key']['value']
    index.rm('key', 'value', a)
    assert_equal [], index.cache['key']['value']
  end
  
  #
  # join test
  #
  
  def test_join_returns_shas_for_specifed_values
    a, b, c = shas('a', 'b', 'c')
    index.add('key', 'one', a)
    index.add('key', 'one', b)
    index.add('key', 'two', c)
    
    assert_equal [a, b].sort, index.join('key', 'one').sort
    assert_equal [a, b, c].sort, index.join('key', 'one', 'two').sort
  end
  
  #
  # select test
  #
  
  def test_select_returns_shas_matching_all_criteria
    a, b, c = shas('a', 'b', 'c')
    index.add('state', 'open', a).add('at', 'one', a)
    index.add('state', 'closed', b).add('at', 'one', b)
    index.add('state', 'open', c).add('at', 'two', c)
    shas = [a, b, c]
    
    assert_equal [a, c], index.select(shas, 'state' => 'open')
    assert_equal [a], index.select(shas, 'state' => 'open', 'at' => 'one')
  end
  
  def test_select_requires_matching_to_all_array_values
    a, b = shas('a', 'b')
    index.add('tags', 'a', a).add('tags', 'b', a)
    index.add('tags', 'a', b).add('tags', 'c', b)
    shas = [a, b]
    
    assert_equal [a], index.select(shas, 'tags' => ['a', 'b'])
    assert_equal [], index.select(shas, 'tags' => ['a', 'd'])
  end
  
  def test_select_only_selects_among_specified_shas
    a, b, c = shas('a', 'b', 'c')
    index.add('state', 'open', a)
    index.add('state', 'open', b)
    index.add('state', 'closed', c)
    
    assert_equal [a], index.select([a, c], 'state' => 'open')
    assert_equal [a, b], index.select([a, b, c], 'state' => 'open')
  end
  
  #
  # filter test
  #
  
  def test_filter_returns_shas_matching_all_criteria
    a, b, c = shas('a', 'b', 'c')
    index.add('state', 'open', a).add('at', 'one', a)
    index.add('state', 'closed', b).add('at', 'one', b)
    index.add('state', 'open', c).add('at', 'two', c)
    shas = [a, b, c]
    
    assert_equal [a, c], index.filter(shas, 'state' => 'closed')
    assert_equal [a, b, c], index.filter(shas, 'state' => 'closed', 'at' => 'two')
  end
  
  def test_filter_removes_any_matching_all_array_values
    a, b = shas('a', 'b')
    index.add('tags', 'a', a).add('tags', 'b', a)
    index.add('tags', 'a', b).add('tags', 'c', b)
    shas = [a, b]
    
    assert_equal [b], index.filter(shas, 'tags' => ['a', 'b'])
    assert_equal [a, b], index.filter(shas, 'tags' => ['a', 'd'])
  end
  
  def test_filter_only_filters_specified_shas
    a, b, c = shas('a', 'b', 'c')
    index.add('state', 'open', a)
    index.add('state', 'closed', b)
    index.add('state', 'closed', c)
    
    assert_equal [b], index.filter([a, b], 'state' => 'open')
    assert_equal [b, c], index.filter([a, b, c], 'state' => 'open')
  end
  
  #
  # write test
  #
  
  def test_write_writes_sha_to_head_file
    a = digest('a')
    index.write(a)
    
    assert_equal a, File.read(index.head_file)
  end
  
  def test_write_writes_map_to_map_file
    a, b = shas('a', 'b', 'c')
    index.map[a] = b
    index.write
    
    assert_equal [[a,b].join].pack("H*"), File.read(index.map_file)
  end
  
  def test_write_writes_cache_to_respective_index_files
    a, b, c = shas('a', 'b', 'c')
    index.add('state', 'open', a)
    index.add('state', 'closed', b)
    index.add('state', 'open', c)
    index.write
    
    assert_equal [[a, c].join].pack("H*"), File.read(index.path('state', 'open'))
    assert_equal [b].pack("H*"), File.read(index.path('state', 'closed'))
  end
  
  #
  # reset test
  #
  
  def test_reset_clears_map
    index.map['a'] = 'b'
    index.reset
    assert_equal({}, index.map)
  end
  
  def test_reset_clears_the_cache
    index.cache['a'] = 'b'
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