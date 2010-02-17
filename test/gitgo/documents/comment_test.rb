require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/documents/comment'

class CommentTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  Comment = Gitgo::Documents::Comment
  
  attr_accessor :comment
  
  def setup
    super
    @current = Repo.set_env(Repo::PATH => method_root.path(:repo))
    @comment = Comment.new
  end
  
  def teardown
    Repo.set_env(@current)
    super
  end
  
  #
  # errors test
  #
  
  def test_errors_detects_missing_re
    comment.re = nil
    assert_equal 'missing', comment.errors['re'].message
  end
end
