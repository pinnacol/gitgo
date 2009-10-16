require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class RepoTest < Test::Unit::TestCase
  Repo = Gitgo::Repo
  
  include RepoTestHelper
  
  attr_writer :repo
  
  # helper to setup the gitgo.git fixture 
  def repo
    @repo ||= Repo.new(setup_repo("gitgo.git"))
  end
  
  def setup
    super
    @repo = nil
  end
  
  #
  # init test
  #
  
  def test_init_initializes_non_existant_repos
    path = method_root[:tmp]
    assert !File.exists?(path)
    
    repo = Repo.init(path)
    
    git_path = method_root.path(:tmp, ".git")
    assert File.exists?(git_path)
    assert_equal git_path, repo.repo.path
    
    repo.add("path" => "content")
    repo.commit("initial commit")
    
    assert_equal "initial commit", repo.current.message
    assert_equal "content", repo.get("path").data
  end
  
  def test_init_initializes_bare_repo_if_specified
    path = method_root[:tmp]
    assert !File.exists?(path)
    
    repo = Repo.init(path, :is_bare => true)
    
    assert !File.exists?(method_root.path(:tmp, ".git"))
    assert File.exists?(path)
    assert_equal path, repo.repo.path
    
    repo.add("path" => "content")
    repo.commit("initial commit")
    
    assert_equal "initial commit", repo.current.message
    assert_equal "content", repo.get("path").data
  end
  
  #
  # user test
  #
  
  def test_user_determines_a_default_user_from_the_repo_config
    user = repo.user
    assert_equal "User One", user.name
    assert_equal "user.one@email.com", user.email
  end
  
  #
  # get test
  #
  
  def contents(tree)
    tree.contents.collect {|obj| obj.name }.sort
  end
  
  def test_get_returns_an_object_corresponding_to_the_path
    tree = repo.get("")
    assert_equal ["comments", "issues", "pages", "users"], contents(tree)
    
    tree = repo.get("/")
    assert_equal ["comments", "issues", "pages", "users"], contents(tree)

    tree = repo.get("/pages")
    assert_equal ["one", "one.txt"], contents(tree)
    
    tree = repo.get("/pages/")
    assert_equal ["one", "one.txt"], contents(tree)
    
    blob = repo.get("/pages/one.txt")
    assert_equal "one.txt", blob.name
    assert_equal %Q{--- 
author: user.one@email.com
date: 2009-09-09 09:00:00 -06:00
--- 
Page one}, blob.data

    assert_equal nil, repo.get("/non_existant")
    assert_equal nil, repo.get("/pages/non_existant.txt")
    assert_equal nil, repo.get("/pages/one.txt/path_under_a_blob")
  end
  
  #
  # AGET test
  #
  
  def test_AGET_returns_tree_objects
    assert_equal ["100644", "703c947591298f9ef248544c67656e966c03600f"], repo["/pages/one.txt"]

    assert_equal({
      "one" =>     ["040000", "681f31a2b2f9557b0d1ec1b1a9203231f4bb0139"], 
      "one.txt" => ["100644", "703c947591298f9ef248544c67656e966c03600f"]
    }, repo["/pages"])
    
    assert_equal(nil, repo["/non_existant"])
    assert_equal(nil, repo["/pages/non_existant.txt"])
    assert_equal(nil, repo["/pages/one.txt/path_under_a_blob"])
  end
  
  def test_AGET_trees_can_dynamically_resolve_and_add_content
    root = repo["/"]
    root.delete("pages")
    
    assert_equal({
      "one" =>     ["040000", "681f31a2b2f9557b0d1ec1b1a9203231f4bb0139"], 
      "one.txt" => ["100644", "703c947591298f9ef248544c67656e966c03600f"]
    }, root["pages"])
    
    assert_equal({}, root["un"]["known"])
    
    assert_equal({
      "comments" =>  ["040000", "2975636a667e91f4d460c4eefb0008164f7a7168"],
      "issues" =>    ["040000", "487866701e307c11f376e20e5e6ba20958006c5f"],
      "pages" => {
        "one" =>     ["040000", "681f31a2b2f9557b0d1ec1b1a9203231f4bb0139"], 
        "one.txt" => ["100644", "703c947591298f9ef248544c67656e966c03600f"]
      },
      "users" =>     ["040000", "a799273ec817022cca6bf7fa51a26751ea3641b6"],
      "un" => {
        "known" => {}
      }
    }, root)
  end
  
  #
  # commit test
  #
  
  def test_commit_raises_error_if_there_are_no_staged_changes
    err = assert_raises(RuntimeError) { repo.commit("no changes!") }
    assert_equal "no changes to commit", err.message
  end
  
  #
  # status test
  #
  
  def test_status_returns_staged_changes
    assert_equal({}, repo.status)
    
    repo.add(
      "/pages/a.txt" => "file a content",
      "/pages/a/b.txt" => "file b content",
      "/pages/a/c.txt" => "file c content"
    )
    
    repo.rm("pages/one", "pages/one.txt", "/pages/a/c.txt")
    
    assert_equal({
      "pages" => {
        "a" => {
          "b.txt" => :add
        },
        "a.txt" => :add,
        "one" => {
          "two.txt" => :rm
        },
        "one.txt" => :rm
      }
    }, repo.status)
  end
  
  #
  # add test
  #
  
  def test_add_adds_the_specified_contents
    repo.add(
      "/pages/a.txt" => "file a content",
      "/pages/a/b.txt" => "file b content",
      "/pages/a/c.txt" => "file c content"
    )
    
    # check the blobs have been added
    mode, id = repo.tree["pages"]["a.txt"]
    blob = repo.repo.blob(id)
    assert_equal %Q{file a content}, blob.data
    
    mode, id = repo.tree["pages"]["a"]["b.txt"]
    blob = repo.repo.blob(id)
    assert_equal %Q{file b content}, blob.data
    
    mode, id = repo.tree["pages"]["a"]["c.txt"]
    blob = repo.repo.blob(id)
    assert_equal %Q{file c content}, blob.data
    
    # check the trees and commit have not been made
    tree = repo.get("/pages")
    assert_equal ["one", "one.txt"], contents(tree)
    
    assert_equal nil, repo.get("/pages/a")
    assert_equal nil, repo.get("/pages/a.txt")
    
    repo.commit("added a file")
    
    # now after the commit check everything is updated
    blob = repo.get("/pages/a.txt")
    assert_equal %Q{file a content}, blob.data
    
    blob = repo.get("/pages/a/b.txt")
    assert_equal %Q{file b content}, blob.data
    
    blob = repo.get("/pages/a/c.txt")
    assert_equal %Q{file c content}, blob.data
    
    tree = repo.get("/pages")
    assert_equal ["a", "a.txt", "one", "one.txt"], contents(tree)
    
    tree = repo.get("/pages/a")
    assert_equal ["b.txt", "c.txt"], contents(tree)
  end
end