require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/index/idx_file'
require 'stringio'

class IdxFileTest < Test::Unit::TestCase
  IdxFile = Gitgo::Index::IdxFile
  acts_as_file_test
  
  attr_accessor :idx_file
  
  INTS = [0, 1, 2, 2147483647]
  PACKED_INTS = INTS.pack('L*')
  
  def setup
    super
    @idx_file = IdxFile.new StringIO.new
  end
  
  #
  # IdxFile.read test
  #
  
  def test_read_reads_all_entries
    path = method_root.prepare(:tmp, "example") {|io| io << PACKED_INTS }
    assert_equal INTS, IdxFile.read(path)
  end
  
  #
  # IdxFile.write test
  #
  
  def test_write_replaces_with_entries
    path = method_root.prepare(:tmp, "example") {|io| io << PACKED_INTS }
    
    IdxFile.write(path, INTS[0,2])
    assert_equal INTS[0,2], IdxFile.read(path)
  end
  
  #
  # IdxFile.append test
  #
  
  def test_append_appends_entries
    path = method_root.prepare(:tmp, "example") {|io| io << PACKED_INTS }
    
    IdxFile.append(path, INTS[0,2])
    assert_equal INTS + INTS[0,2], IdxFile.read(path)
  end
  
  #
  # IdxFile.rm test
  #
  
  def test_rm_removes_entries
    path = method_root.prepare(:tmp, "example") {|io| io << PACKED_INTS }
    
    IdxFile.rm(path, *INTS[0,2])
    assert_equal INTS[2,3], IdxFile.read(path)
  end
end