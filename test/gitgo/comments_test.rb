require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/comments'

class CommentsTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  def app
    Gitgo::Comments
  end
  
  def setup_app(repo)
    repo = Gitgo::Repo.new(setup_repo(repo))
    app.set :repo, repo
    app.instance_variable_set :@prototype, nil
    repo
  end
  
  def timestamp
    Time.now.strftime("%Y/%m/%d")
  end
  
  #
  # post test
  #

  def test_post_creates_document_and_updates_parent_in_timeline
    repo = setup_app("gitgo.git")
    parent = "c1a80236d015d612d6251fca9611847362698e1c"
    post("/comment/#{parent}", "content" => "new doc content", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    assert_equal "new doc content", repo.doc(new_sha).content
    assert repo.links(parent).include?(new_sha)
    assert repo[timestamp].include?(parent)
  end

  def test_post_without_parent_creates_document_and_updates_doc_in_timeline
    repo = setup_app("gitgo.git")
    post("/comment", "content" => "new doc content", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    assert_equal "new doc content", repo.doc(new_sha).content
    assert repo[timestamp].include?(new_sha)
  end
  
  def test_post_adds_blob_but_does_not_commit_new_content_unless_commit_is_true
    repo = setup_app("gitgo.git")
    post("/comment", "content" => "new doc content")
    assert last_response.redirect?, last_response.body
    
    new_sha = last_response['Sha']
    assert_equal "new doc content", repo.doc(new_sha).content
    
    assert_equal nil, repo[timestamp]
    repo.commit("commit changes")
    assert repo[timestamp].include?(new_sha)
  end
end