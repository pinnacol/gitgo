require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/comments'

class CommentsUtilsTest < Test::Unit::TestCase
  include RepoTestHelper
  include Gitgo::Comments::Utils
  
  attr_accessor :repo
  
  def setup
    super
    @repo = Gitgo::Repo.new setup_repo('gitgo.git')
  end
  
  #
  # latest test
  #
  
  def test_latest_returns_the_latest_shas
    assert_equal [
      "11361c0dbe9a65c223ff07f084cceb9c6cf3a043",
      "3a2662fad86206d8562adbf551855c01f248d4a2",
      "dfe0ffed95402aed8420df921852edf6fcba2966"
    ], latest
  end
end