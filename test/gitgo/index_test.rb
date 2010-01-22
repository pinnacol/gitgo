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