require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/repo'

class RepoControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  Document = Gitgo::Document
  
  attr_reader :app
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init setup_repo("simple.git")
    @app = Gitgo::Controllers::Repo.new(nil, repo)
  end
  
  def git
    repo.git
  end
  
  #
  # index test
  #
  
  def test_index_shows_current_commit
    sha = repo.save({})
    repo.commit!
    
    get("/repo")
    assert last_response.ok?
    assert last_response.body.include?(sha)
  end
  
  #
  # status test
  #
  
  def test_status_shows_current_state
    git.checkout('master')
    
    get("/repo/status")
    assert last_response.ok?
    assert last_response.body.include?('No changes')
    
    git["newfile.txt"] = "new content"
    git["one/two.txt"] = nil
    
    get("/repo/status")
    assert last_response.ok?
    
    assert_match(/class="add".*newfile\.txt/, last_response.body)
    assert_match(/class="rm".*one\/two\.txt/, last_response.body)
  end
  
  #
  # maintenance test
  #
  
  def test_maintenance_shows_no_issues_for_clean_repo
    get("/repo/maintenance")
    assert last_response.ok?
    assert last_response.body.include?("No issues found")
  end
  
  def test_maintenance_shows_issues_for_repo_with_issues
    sha = git.set(:blob, "blah blah blob")
    
    get("/repo/maintenance")
    assert last_response.ok?
    assert !last_response.body.include?("No issues found")
    assert last_response.body =~ /dangling blob.*#{sha}/
  end
  
  #
  # reference test
  #
  
  def test_references_are_available
    get("/repo/reference")
    assert last_response.ok?
    
    get("/repo/reference/design")
    assert last_response.ok?
  end
  
  #
  # prune test
  #
  
  def test_prune_prunes_dangling_blobs
    sha = git.set(:blob, "blah blah blob")
    
    get("/repo/maintenance")
    assert last_response.body =~ /dangling blob.*#{sha}/
    
    post("/repo/prune")
    assert last_response.redirect?
    assert_equal "/repo/maintenance", last_response['Location']
    
    follow_redirect!
    assert last_response.body.include?("No issues found")
  end
  
  #
  # gc test
  #
  
  def test_gc_packs_repo
    sha = repo.save('content' => 'new document')
    repo.create(sha)
    repo.commit!
    
    get("/repo/maintenance")
    assert last_response.body =~ /count[^\d]+?5/m
    
    post("/repo/gc")
    assert last_response.redirect?
    assert_equal "/repo/maintenance", last_response['Location']
    
    follow_redirect!
    assert last_response.body =~ /count[^\d]+?0/m
  end
  
  #
  # update test
  #
  
  def test_update_pulls_changes_then_pushes_changes_if_specified
    one = repo.scope { Document.create("content" => "one").sha }
    repo.commit!
    
    clone = git.clone(method_root.path(:tmp, 'clone'))
    clone.track('origin/gitgo')
    clone = Gitgo::Repo.new(Gitgo::Repo::GIT => clone)
    
    two = repo.scope { Document.create("content" => "two").sha }
    repo.commit!
    
    three = clone.scope { Document.create("content" => "three").sha }
    clone.commit!
    
    @app = Gitgo::Controllers::Repo.new(nil, clone)
    
    assert_equal "one", repo.read(one)['content']
    assert_equal "two", repo.read(two)['content']
    assert_equal nil, repo.read(three)
    
    assert_equal "one", clone.read(one)['content']
    assert_equal nil, clone.read(two)
    assert_equal "three", clone.read(three)['content']
    
    # pull only
    post("/repo/update", :sync => false)
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    assert_equal "one", repo.read(one)['content']
    assert_equal "two", repo.read(two)['content']
    assert_equal nil, repo.read(three)
    
    assert_equal "one", clone.read(one)['content']
    assert_equal "two", clone.read(two)['content']
    assert_equal "three", clone.read(three)['content']
    
    # now with a push
    post("/repo/update", :sync => true)
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    assert_equal "one", repo.read(one)['content']
    assert_equal "two", repo.read(two)['content']
    assert_equal "three", repo.read(three)['content']
    
    assert_equal "one", clone.read(one)['content']
    assert_equal "two", clone.read(two)['content']
    assert_equal "three", clone.read(three)['content']
  end
  
  #
  # reset test
  #
  
  def test_reset_clears_index_and_performs_full_reindex
    sha = repo.scope { Document.create("content" => "document", "tags" => ["a", "b"]).sha }
    repo.commit!
    
    index = repo.index
    index.reset
    
    b_index = index.path(Gitgo::Index::FILTER, "tags", "b")
    FileUtils.rm(b_index)
    
    fake_index = index.path(Gitgo::Index::FILTER, "tags", "c")
    Gitgo::Index::IdxFile.write(fake_index, index.idx(sha))
    
    get("/repo/index/tags/a")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/index/tags/b")
    assert last_response.ok?
    assert !last_response.body.include?(sha)
    
    get("/repo/index/tags/c")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    post("/repo/reset")
    
    get("/repo/index/tags/a")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/index/tags/b")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/index/tags/c")
    assert last_response.ok?
    assert !last_response.body.include?(sha)
  end
end