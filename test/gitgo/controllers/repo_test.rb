require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/repo'

class RepoControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.new(setup_repo("simple.git"))
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Controllers::Repo
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
    assert last_response.body =~ /class="add">alpha\.txt.*#{content['alpha.txt'][1]}/, last_response.body
    assert last_response.body =~ /class="rm">one\/two\.txt.*#{content['one/two.txt'][1]}/
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
    assert last_response.body.include?('class="count-stat">5<')
    
    post("/repo/gc")
    assert last_response.redirect?
    assert_equal "/repo/maintenance", last_response['Location']
    
    follow_redirect!
    assert last_response.body.include?('class="count-stat">0<')
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
    app.set :repo, clone
    app.instance_variable_set :@prototype, nil
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal nil, repo.read(three)
    
    assert_equal "one document", clone.read(one).content
    assert_equal nil, clone.read(two)
    assert_equal "three document", clone.read(three).content
    
    post("/repo/update")
    assert last_response.redirect?
    assert_equal "/repo/status", last_response['Location']
    
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
    app.set :repo, clone
    app.instance_variable_set :@prototype, nil
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal nil, repo.read(three)
    
    assert_equal "one document", clone.read(one).content
    assert_equal nil, clone.read(two)
    assert_equal "three document", clone.read(three).content
    
    post("/repo/update", :push => true)
    assert last_response.redirect?, last_response.body
    assert_equal "/repo/status", last_response['Location']
    
    assert_equal "one document", repo.read(one).content
    assert_equal "two document", repo.read(two).content
    assert_equal "three document", repo.read(three).content
    
    assert_equal "one document", clone.read(one).content
    assert_equal "two document", clone.read(two).content
    assert_equal "three document", clone.read(three).content
  end
end