require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/documents/issue'

class IssueTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  Issue = Gitgo::Documents::Issue
  
  attr_accessor :issue
  
  def setup
    super
    @current = Repo.set_env(Repo::PATH => method_root.path(:repo))
    @issue = Issue.new
  end
  
  def teardown
    Repo.set_env(@current)
    super
  end
  
  #
  # find test
  #
  
  def test_find_returns_original_issue
    orig = Issue.create('title' => 'original')
    up = Issue.update(orig, 'title' => 'up')
    
    assert_equal orig.sha, up.origin
    assert_equal [orig], Issue.find('shas' => [up.sha])
  end
  
  def test_find_searches_issues_by_tails
    a = Issue.create('title' => 'original', 'tags' => ['open'])
    b = Issue.create('tags' => 'closed', 'origin' => a, 'parents' => [a])
    assert_equal [a], Issue.find('tags' => ['closed'])
    
    c = Issue.create('tags' => 'open', 'origin' => a, 'parents' => [b])
    assert_equal [], Issue.find('tags' => ['closed'])
  end
end
