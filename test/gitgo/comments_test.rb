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
  
  def timestamp
    Time.now.strftime("%Y/%m/%d")
  end
  
  #
  # post test
  #

  def test_post_creates_document_and_updates_parent_in_timeline
    parent = repo.write("blob", "parent content")
    
    post("/comment/#{parent}", "content" => "new content", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    
    assert_equal "new content", repo.doc(new_sha).content
    assert repo.links(parent).include?(new_sha)
    assert repo[timestamp].include?(parent)
    assert !repo[timestamp].include?(new_sha)
  end

  def test_post_without_parent_creates_document_and_updates_doc_in_timeline
    post("/comment", "content" => "new content", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    
    assert_equal "new content", repo.doc(new_sha).content
    assert repo[timestamp].include?(new_sha)
  end
  
  def test_post_adds_blob_but_does_not_commit_new_content_unless_commit_is_true
    post("/comment", "content" => "new content")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    assert_equal "new content", repo.doc(new_sha).content
    assert_equal nil, repo[timestamp]
    
    repo.commit("commit changes")
    assert repo[timestamp].include?(new_sha)
  end
  
  #
  # update test
  #
  
  def test_update_updates_previous_comment_with_new_comment
    parent = repo.create("parent")
    child =  repo.create("original content", "a" => "A")
    repo.register(timestamp, parent, :flat => true).link(parent, child).commit("added fixture")
    
    assert_equal "original content", repo.doc(child).content
    assert_equal "A", repo.doc(child).attributes["a"]
    
    put("/comment/#{parent}/#{child}", "content" => "new content", "attributes" => {"a" => "B"}, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    
    assert !repo.links(parent).include?(child)
    assert repo.links(parent).include?(new_sha)
    assert repo[timestamp].include?(parent)
    
    assert_equal "new content", repo.doc(new_sha).content
    assert_equal "B", repo.doc(new_sha).attributes["a"]
  end
  
  #
  # destroy test
  #

  def test_destroy_removes_comment_from_parent_and_parent_from_timeline
    parent = repo.create("parent content")
    child =  repo.create("child comment")
    repo.register(timestamp, parent, :flat => true).link(parent, child).commit("added fixture")
    
    assert repo.links(parent).include?(child)
    assert repo[timestamp].include?(parent)

    delete("/comment/#{parent}/#{child}", "commit" => "true")
    assert last_response.redirect?, last_response.body

    assert !repo.links(parent).include?(child)
    assert !repo[timestamp].include?(parent)
  end
  
  def test_destroy_does_not_remove_parent_from_timeline_if_other_comments_exist_for_that_parent_and_time
    parent = repo.create("parent content")
    a =  repo.create("comment a")
    b =  repo.create("comment b")
    
    repo.register(timestamp, parent, :flat => true)
    repo.link(parent, a)
    repo.link(parent, b)
    repo.commit("added fixture")
    
    assert repo[timestamp].include?(parent)

    delete("/comment/#{parent}/#{a}", "commit" => "true")
    assert last_response.redirect?

    assert !repo.links(parent).include?(a)
    assert repo[timestamp].include?(parent)
    
    delete("/comment/#{parent}/#{b}", "commit" => "true")
    
    assert !repo.links(parent).include?(b)
    assert !repo[timestamp].include?(parent)
  end
  
  def test_destroy_removes_comment_from_timeline_if_no_parent_is_specified
    comment =  repo.create("comment")
    repo.register(timestamp, comment, :flat => true).commit("added fixture")
    
    assert repo[timestamp].include?(comment)

    delete("/comment/#{comment}", "commit" => "true")
    assert !repo[timestamp].include?(comment)
  end
  
  def test_destroy_does_not_commit_unless_specified
    comment =  repo.create("comment")
    repo.register(timestamp, comment, :flat => true).commit("added fixture")
    
    assert repo[timestamp].include?(comment)

    delete("/comment/#{comment}")
    assert repo[timestamp].include?(comment)
    
    repo.commit("ok now committed")
    assert !repo[timestamp].include?(comment)
  end
end