require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/repo'

class RepoControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :app
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.new(setup_repo("simple.git"))
    @app = Gitgo::Controllers::Repo.new(nil, repo)
  end
  
  #
  # status test
  #
  
  def test_status_shows_current_state
    repo.checkout('master')
    
    get("/repo/status")
    assert last_response.ok?
    assert last_response.body.include?('No changes')
    
    content = {"alpha.txt" => "alpha content", "one/two.txt" => nil}
    repo.add(content, true)
    
    assert_equal({"alpha.txt"=>:add, "one/two.txt"=>:rm}, repo.status)
    
    get("/repo/status")
    assert last_response.ok?
    
    alpha_sha = content['alpha.txt'][1]
    assert last_response.body =~ /class="add".*#{alpha_sha}.*alpha\.txt/
    
    one_two_sha = content['one/two.txt'][1]
    assert last_response.body =~ /class="rm".*#{one_two_sha}.*one\/two\.txt/
  end
  
  #
  # setup test
  #
  
  def test_setup_sets_up_a_new_gitgo_branch
    assert_equal 'gitgo', repo.branch
    assert_equal nil, repo.grit.refs.find {|ref| ref.name == 'gitgo' }
    
    post("/repo/setup")
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    gitgo = repo.grit.refs.find {|ref| ref.name == 'gitgo' }
    assert_equal 'initial commit', gitgo.commit.message
    assert_equal gitgo.commit.sha, repo.head
  end
  
  def test_setup_sets_up_tracking_of_specified_remote
    assert_equal 'gitgo', repo.branch
    assert_equal nil, repo.grit.refs.find {|ref| ref.name == 'gitgo' }
    
    post("/repo/setup", :remote => 'caps')
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    caps = repo.grit.refs.find {|ref| ref.name == 'caps' }
    gitgo = repo.grit.refs.find {|ref| ref.name == 'gitgo' }
    
    assert_equal gitgo.commit.sha, caps.commit.sha
    assert_equal gitgo.commit.sha, repo.head
  end
  
  def test_remote_tracking_setup_reindexes_repo
    repo.checkout('remote')
    sha = repo.create("initialized gitgo", 'tags' => ['tag'])
    repo.commit!("initial commit")
    repo.checkout('gitgo')
    
    post("/repo/setup", :remote => 'remote')
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
    id = repo.set(:blob, "blah blah blob")
    
    get("/repo/maintenance")
    assert last_response.ok?
    assert !last_response.body.include?("No issues found")
    assert last_response.body =~ /dangling blob.*#{id}/
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
    id = repo.set(:blob, "blah blah blob")
    
    get("/repo/maintenance")
    assert last_response.body =~ /dangling blob.*#{id}/
    
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
    repo.create("new document")
    repo.commit("new commit")
    
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
    one = repo.create("one document")
    repo.commit("added document")
    
    clone = repo.clone(method_root.path(:tmp, 'clone'))
    clone.sandbox do |git, w, i|
      git.branch({:track => true}, 'gitgo', 'origin/gitgo')
    end
    
    two = repo.create("two document")
    repo.commit("added document")
    
    three = clone.create("three document")
    clone.commit("added document")
    
    #
    app.repo = clone
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal nil, repo.read(three)
    
    assert_equal "one document", clone.read(one).content
    assert_equal nil, clone.read(two)
    assert_equal "three document", clone.read(three).content
    
    post("/repo/update", :sync => false)
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal nil, repo.read(three)
    
    assert_equal "one document", clone.read(one).content
    assert_equal "two document", clone.read(two).content
    assert_equal "three document", clone.read(three).content
  end
  
  def test_update_pulls_changes_then_pushes_changes_if_specified
    one = repo.create("one document")
    repo.commit("added document")
    
    clone = repo.clone(method_root.path(:tmp, 'clone'))
    clone.sandbox do |git, w, i|
      git.branch({:track => true}, 'gitgo', 'origin/gitgo')
    end
    
    two = repo.create("two document")
    repo.commit("added document")
    
    three = clone.create("three document")
    clone.commit("added document")
    
    #
    app.repo = clone
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal nil, repo.read(three)
    
    assert_equal "one document", clone.read(one).content
    assert_equal nil, clone.read(two)
    assert_equal "three document", clone.read(three).content
    
    post("/repo/update", :sync => true)
    assert last_response.redirect?
    assert_equal "/repo", last_response['Location']
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal "three document", repo.read(three).content
    
    assert_equal "one document", clone.read(one).content
    assert_equal "two document", clone.read(two).content
    assert_equal "three document", clone.read(three).content
  end
  
  #
  # reindex test
  #
  
  def test_reindex_clears_index_and_performs_full_reindex
    sha = repo.create("document", "tags" => ["a", "b"])
    repo.commit!("added document")
    repo.index.reset
    
    b_index = repo.index.path("tags", "b")
    FileUtils.rm(b_index)
    
    fake_index = repo.index.path("tags", "c")
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
    sha = repo.create("document", "tags" => ["a", "b"])
    repo.commit!("added document")
    repo.index.reset
    
    b_index = repo.index.path("tags", "b")
    FileUtils.rm(b_index)
    
    fake_index = repo.index.path("tags", "c")
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