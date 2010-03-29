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
    orig = Issue.create('title' => 'original', 'state' => 'open')
    up = Issue.update(orig, 'title' => 'up')
    
    assert_equal orig.sha, up.origin
    assert_equal [orig], Issue.find('shas' => [up.sha])
  end
  
  def test_find_searches_issues_by_tails
    a = Issue.create('title' => 'original', 'state' => 'open')
    b = Issue.create('state' => 'closed', 'origin' => a, 'parents' => [a])
    assert_equal [a], Issue.find('state' => 'closed')
    
    c = Issue.create('state' => 'open', 'origin' => a, 'parents' => [b])
    assert_equal [], Issue.find('state' => 'closed')
  end
  
  def test_find_does_not_return_duplicate_issues_for_multiple_matching_tails
    a = Issue.create('title' => 'original', 'state' => 'open')
    b = Issue.create('tags' => 'b', 'state' => 'open', 'origin' => a, 'parents' => [a])
    c = Issue.create('tags' => 'c', 'state' => 'open', 'origin' => a, 'parents' => [a])
    
    assert_equal [a], Issue.find(nil, 'tags' => ['b', 'c'])
  end
  
  #
  # titles test
  #
  
  def test_titles_returns_all_head_titles
    a = Issue.create('title' => 'original', 'state' => 'open')
    assert_equal ['original'], a.titles
    
    b = Issue.update(a.sha, 'title' => 'b', 'state' => 'open')
    assert_equal ['b'], a.reset.titles
    
    c = Issue.update(a.sha, 'title' => 'c', 'state' => 'open')
    assert_equal ['b', 'c'], a.reset.titles.sort
  end
  
  #
  # current_tags test
  #
  
  def test_current_tags_returns_all_unique_tail_tags
    a = Issue.create('title' => 'original', 'state' => 'open', 'tags' => ['a', 'b'])
    assert_equal ['a', 'b'], a.current_tags.sort
    
    b = Issue.create('tags' => ['c', 'd'], 'state' => 'open', 'origin' => a, 'parents' => [a])
    assert_equal ['c', 'd'], a.reset.current_tags.sort
    
    c = Issue.create('tags' => ['d', 'e'], 'state' => 'open', 'origin' => a, 'parents' => [a])
    assert_equal ['c', 'd', 'e'], a.reset.current_tags.sort
  end
  
  #
  # current_states test
  #
  
  def test_current_states_returns_all_unique_states
    a = Issue.create('title' => 'original', 'state' => 'open')
    assert_equal ['open'], a.current_states.sort
    
    b = Issue.create('state' => 'closed', 'origin' => a, 'parents' => [a])
    assert_equal ['closed'], a.reset.current_states.sort
    
    c = Issue.create('state' => 'open', 'origin' => a, 'parents' => [a])
    assert_equal ['closed', 'open'], a.reset.current_states.sort
  end
end
