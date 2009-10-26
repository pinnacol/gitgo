require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/comments'

class CommentsTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root[:tmp], :bare => true)
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Comments
  end
  
  #
  # post test
  #

  def test_post_creates_document
    a = repo.write("blob", "a")
    
    post("/comment/#{a}", "content" => "new content", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    b = last_response['Sha']
    
    assert_equal "new content", repo.read(b).content
    assert_equal [b], repo.children(a)
  end

  # def test_post_without_parent_creates_document
  #   post("/comment", "content" => "new content", "commit" => "true")
  #   assert last_response.redirect?, last_response.body
  #   
  #   new_sha = last_response['Sha']
  #   
  #   assert_equal "new content", repo.read(new_sha).content
  #   assert repo[timestamp].include?(new_sha)
  # end
  
  def test_post_adds_blob_but_does_not_commit_links_unless_commit_is_true
    a = repo.write("blob", "a")
    
    post("/comment/#{a}", "content" => "new content")
    assert last_response.redirect?, last_response.body
    
    b = last_response['Sha']
    
    assert_equal "new content", repo.read(b).content
    assert_equal [], repo.children(a)
    
    repo.commit("ok now committed")
    assert_equal [b], repo.children(a)
  end
  
  #
  # update test
  #
  
  def test_update_updates_and_replaces_previous_comment_with_new_comment
    a = repo.create("a")
    b = repo.create("b", "key" => "value")
    c = repo.create("c")
    repo.link(a, b).link(b, c).commit("added fixture")
    
    assert_equal [b], repo.children(a)
    assert_equal [c], repo.children(b)
    
    assert_equal "b", repo.read(b).content
    assert_equal "value", repo.read(b).attributes["key"]
    
    put("/comment/#{a}/#{b}", "content" => "B", "attributes" => {"key" => "VALUE"}, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    new_b = last_response['Sha']
    
    assert_equal [new_b], repo.children(a)
    assert_equal [], repo.children(b)
    assert_equal [c], repo.children(new_b)
    
    assert_equal "B", repo.read(new_b).content
    assert_equal "VALUE", repo.read(new_b).attributes["key"]
  end
  
  #
  # destroy test
  #
  
  def test_destroy_removes_comment_from_parent
    a = repo.create("a")
    b = repo.create("b")
    c = repo.create("c")
    repo.link(a, b).link(a, c).commit("added fixture")
    
    assert_equal [b, c].sort, repo.children(a).sort
  
    delete("/comment/#{a}/#{b}", "commit" => "true")
    assert last_response.redirect?, last_response.body
  
    assert_equal [c], repo.children(a)
  end
  
  def test_destroy_removes_comment_from_parent_recursively_if_specified
    a = repo.create("a")
    b = repo.create("b")
    c = repo.create("c")
    repo.link(a, b).link(b, c).commit("added fixture")
    
    assert_equal [b], repo.children(a)
    assert_equal [c], repo.children(b)
  
    delete("/comment/#{a}/#{b}", "commit" => "true", "recursive" => "true")
    assert last_response.redirect?, last_response.body
  
    assert_equal [], repo.children(a)
    assert_equal [], repo.children(b)
  end
  
  def test_destroy_does_not_commit_unless_specified
    a = repo.create("a")
    b = repo.create("b")
    repo.link(a, b).commit("added fixture")
    assert_equal [b], repo.children(a)
  
    delete("/comment/#{a}/#{b}")
    assert_equal [b], repo.children(a)
    
    repo.commit("ok now committed")
    assert_equal [], repo.children(a)
  end
end