require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/repo'

class RepoControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
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
  
  def test_index_shows_setup_form_for_repos_without_a_gitgo_branch
    get("/repo")
    assert last_response.ok?
    assert last_response.body.include?('action="/repo/setup"')
    
    repo.store({})
    repo.commit!
    
    get("/repo")
    assert last_response.ok?
    assert !last_response.body.include?('action="/repo/setup"')
  end
  
  def test_index_shows_current_commit
    sha = repo.store({})
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
  # setup test
  #
  
  def test_setup_sets_up_a_new_gitgo_branch
    assert_equal nil, git.head
    assert_equal nil, git.grit.refs.find {|ref| ref.name == git.branch }
    
    post("/repo/setup")
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    gitgo = git.grit.refs.find {|ref| ref.name == git.branch }
    assert_equal gitgo.commit.sha, git.head
  end
  
  def test_setup_sets_up_tracking_of_specified_remote
    @repo = Gitgo::Repo.new Gitgo::Repo::GIT => git.clone(method_root.path('clone'))
    @app = Gitgo::Controllers::Repo.new(nil, repo)
    
    assert_equal nil, git.head
    
    post("/repo/setup", :track => 'origin/caps')
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    # the caps head
    assert_equal '19377b7ec7b83909b8827e52817c53a47db96cf0', git.head
  end
  
  def test_remote_tracking_setup_reindexes_repo
    git.checkout('track')
    sha = repo.store('content' => 'new doc', 'tags' => ['tag'])
    repo.commit!
    git.checkout('gitgo')
    
    @repo = Gitgo::Repo.new Gitgo::Repo::GIT => git.clone(method_root.path('clone'))
    @app = Gitgo::Controllers::Repo.new(nil, repo)
    
    post("/repo/setup", :track => 'origin/track')
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    get("/repo/idx/tags/tag")
    assert last_response.ok?
    assert last_response.body.include?(sha)
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
    repo.store('content' => 'new document')
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
  
  def test_update_pulls_changes
    one = Gitgo::Document.new({"content" => "one"}, repo).save
    repo.commit!
    
    clone = git.clone(method_root.path(:tmp, 'clone'))
    clone.track('origin/gitgo')
    clone = Gitgo::Repo.new(Gitgo::Repo::GIT => clone)
    
    two = Gitgo::Document.new({"content" => "two"}, repo).save
    repo.commit!
    
    three = Gitgo::Document.new({"content" => "three"}, clone).save
    clone.commit!
    
    #
    @app = Gitgo::Controllers::Repo.new(nil, clone)
    
    assert_equal "one", repo.read(one)['content']
    assert_equal "two", repo.read(two)['content']
    assert_equal nil, repo.read(three)
    
    assert_equal "one", clone.read(one)['content']
    assert_equal nil, clone.read(two)
    assert_equal "three", clone.read(three)['content']
    
    post("/repo/update", :sync => false)
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    assert_equal "one", repo.read(one)['content']
    assert_equal "two", repo.read(two)['content']
    assert_equal nil, repo.read(three)
    
    assert_equal "one", clone.read(one)['content']
    assert_equal "two", clone.read(two)['content']
    assert_equal "three", clone.read(three)['content']
  end
  
  def test_update_pulls_changes_then_pushes_changes_if_specified
    one = Gitgo::Document.new({"content" => "one"}, repo).save
    repo.commit!
    
    clone = git.clone(method_root.path(:tmp, 'clone'))
    clone.track('origin/gitgo')
    clone = Gitgo::Repo.new(Gitgo::Repo::GIT => clone)
    
    two = Gitgo::Document.new({"content" => "two"}, repo).save
    repo.commit!
    
    three = Gitgo::Document.new({"content" => "three"}, clone).save
    clone.commit!
    
    #
    @app = Gitgo::Controllers::Repo.new(nil, clone)
    
    assert_equal "one", repo.read(one)['content']
    assert_equal "two", repo.read(two)['content']
    assert_equal nil, repo.read(three)
    
    assert_equal "one", clone.read(one)['content']
    assert_equal nil, clone.read(two)
    assert_equal "three", clone.read(three)['content']
    
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
  # reindex test
  #
  
  def test_reindex_clears_index_and_performs_full_reindex
    sha = Gitgo::Document.new({"content" => "document", "tags" => ["a", "b"]}, repo).save
    repo.commit!
    
    idx = repo.idx
    idx.reset
    
    b_index = idx.path("tags", "b")
    FileUtils.rm(b_index)
    
    fake_index = idx.path("tags", "c")
    Gitgo::Index::IndexFile.write(fake_index, sha)
    
    get("/repo/idx/tags/a")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/idx/tags/b")
    assert last_response.ok?
    assert !last_response.body.include?(sha)
    
    get("/repo/idx/tags/c")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    post("/repo/reindex")
    
    get("/repo/idx/tags/a")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/idx/tags/b")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/idx/tags/c")
    assert last_response.ok?
    assert !last_response.body.include?(sha)
  end
  
  #
  # reset test
  #
  
  def test_reset_clears_index_and_performs_full_reindex
    sha = Gitgo::Document.new({"content" => "document", "tags" => ["a", "b"]}, repo).save
    repo.commit!
    
    idx = repo.idx
    idx.reset
    
    b_index = idx.path("tags", "b")
    FileUtils.rm(b_index)
    
    fake_index = idx.path("tags", "c")
    Gitgo::Index::IndexFile.write(fake_index, sha)
    
    get("/repo/idx/tags/a")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/idx/tags/b")
    assert last_response.ok?
    assert !last_response.body.include?(sha)
    
    get("/repo/idx/tags/c")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    post("/repo/reset")
    
    get("/repo/idx/tags/a")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/idx/tags/b")
    assert last_response.ok?
    assert last_response.body.include?(sha)
    
    get("/repo/idx/tags/c")
    assert last_response.ok?
    assert !last_response.body.include?(sha)
  end
end