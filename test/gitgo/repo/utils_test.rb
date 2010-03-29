require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/repo/utils'

class RepoUtilsTest < Test::Unit::TestCase
  include Gitgo::Repo::Utils
  
  #
  # sha_path test
  #
  
  def test_sha_path_splits_sha_into_ab_xyz_format
    assert_equal ['ab', 'xyz'], sha_path('abxyz')
  end
end