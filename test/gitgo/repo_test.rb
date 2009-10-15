require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class RepoTest < Test::Unit::TestCase
  Repo = Gitgo::Repo
  
  include RepoTestHelper
  
  attr_accessor :repo
  
  def setup
    super
    @repo = Repo.new(setup_repo("gitgo.git"))
  end
  
  #
  # commit test
  #
  
  def test_commit
    repo.branch = "3477b8e166167db65b3a44101f7a362ba5239764"
    assert_equal "initial import of fixture data", repo.commit.message
  end
  
  def test_commit_raises_error_on_invalid_branch
    repo.branch = "non_existant"
    err = assert_raises(RuntimeError) { repo.commit }
    assert_equal "invalid branch: non_existant", err.message
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
  # put test
  #
  
  def test_put_writes_content_to_the_specified_path
    repo.put("/path/to/file.txt", "file content")
    repo.store.commit("added a file")
    
    tree = repo.get("")
    assert_equal ["comments", "issues", "pages", "path", "users"], contents(tree)

    tree = repo.get("/path/to")
    assert_equal ["file.txt"], contents(tree)
    
    blob = repo.get("/path/to/file.txt")
    assert_equal %Q{file content}, blob.data
  end
end