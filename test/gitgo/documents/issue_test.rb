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
  
  def test_find_searches_issues_by_tails
    a = Issue.create('state' => 'open')
    b = Issue.create({'state' => 'closed'}, a)
    assert_equal [a], Issue.find('state' => 'closed')
    
    c = Issue.create({'state' => 'open'}, b)
    assert_equal [], Issue.find('state' => 'closed')
  end
  
  def test_find_does_not_return_duplicate_issues_for_multiple_matching_tails
    a = Issue.create('state' => 'open')
    b = Issue.create({'state' => 'closed'}, a)
    c = Issue.create({'state' => 'closed'}, a)
    
    assert_equal [a], Issue.find(nil, 'state' => 'closed')
  end
  
  #
  # graph_heads test
  #
  
  def test_graph_heads_returns_current_versions_of_graph_head
    a = Issue.create('title' => 'a', 'state' => 'open')
    b = Issue.update(a, 'title' => 'b')
    c = Issue.update(a, 'title' => 'c')
    d = Issue.create({'title' => 'd', 'state' => 'open'}, b)
    
    a.reset
    assert_equal ['b', 'c'], a.graph_heads.collect {|head| head.title }.sort
    
    d.reset
    assert_equal ['b', 'c'], d.graph_heads.collect {|head| head.title }.sort
  end
  
  #
  # graph_tails test
  #
  
  def test_graph_tails_returns_all_graph_tails
    a = Issue.create('title' => 'a', 'state' => 'open')
    b = Issue.create({'title' => 'b', 'state' => 'open'}, a)
    c = Issue.update(b, 'title' => 'c')
    d = Issue.create({'title' => 'd', 'state' => 'open'}, a)
    
    a.reset
    assert_equal ['c', 'd'], a.graph_tails.collect {|tail| tail.title }.sort
    
    d.reset
    assert_equal ['c', 'd'], d.graph_tails.collect {|tail| tail.title }.sort
  end
  
end
