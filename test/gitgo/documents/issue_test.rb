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
  
  def test_find_does_not_return_duplicate_issues_for_multiple_matching_tails
    a = Issue.create('title' => 'original', 'tags' => ['open'])
    b = Issue.create('tags' => 'b', 'origin' => a, 'parents' => [a])
    c = Issue.create('tags' => 'c', 'origin' => a, 'parents' => [a])
    
    assert_equal [a], Issue.find(nil, 'tags' => ['b', 'c'])
  end
  
  #
  # current_titles test
  #
  
  def test_current_titles_returns_all_tail_titles
    a = Issue.create('title' => 'original')
    assert_equal ['original'], a.current_titles
    
    b = Issue.create('title' => 'b', 'origin' => a, 'parents' => [a])
    assert_equal ['b'], a.reset.current_titles
    
    c = Issue.create('title' => 'c', 'origin' => a, 'parents' => [a])
    assert_equal ['b', 'c'], a.reset.current_titles.sort
  end
  
  #
  # current_tags test
  #
  
  def test_current_tags_returns_all_unique_tail_tags
    a = Issue.create('title' => 'original', 'tags' => ['a', 'b'])
    assert_equal ['a', 'b'], a.current_tags.sort
    
    b = Issue.create('tags' => ['c', 'd'], 'origin' => a, 'parents' => [a])
    assert_equal ['c', 'd'], a.reset.current_tags.sort
    
    c = Issue.create('tags' => ['d', 'e'], 'origin' => a, 'parents' => [a])
    assert_equal ['c', 'd', 'e'], a.reset.current_tags.sort
  end
end
