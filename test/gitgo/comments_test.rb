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
end