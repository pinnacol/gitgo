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
  
  def test_errors_detects_missing_origin
    comment.origin = nil
    assert_equal 'missing', comment.errors['origin'].message
  end
  
  def test_errors_detects_missing_origin_even_if_sha_is_specified
    sha = Repo.current.store
    
    comment.origin = nil
    comment.reset(sha)
    
    assert_equal 'missing', comment.errors['origin'].message
  end
end
