require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class RepoTest < Test::Unit::TestCase
  include RepoTestHelper
  Repo = Gitgo::Repo
  
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
  # documentation test
  #
  
  def test_repo_documentation
    repo = Repo.init(method_root.path(:tmp, "example"), :user => "John Doe <jdoe@example.com>")
    repo.add(
      "README" => "New Project",
      "lib/project.rb" => "module Project\nend",
      "remove_this_file" => "won't be here long...")

    repo.commit("setup a new project")

    repo.rm("remove_this_file")
    repo.commit("removed extra file")

    assert_equal ["README", "lib"], repo["/"]
    assert_equal "module Project\nend", repo["/lib/project.rb"]
    assert_equal nil, repo["/remove_this_file"]

    repo.branch = "gitgo^"
    assert_equal "won't be here long...", repo["/remove_this_file"]

    assert_equal "cad0dc0df65848aa8f3fee72ce047142ec707320", repo.get("/lib").id
    assert_equal "636e25a2c9fe1abc3f4d3f380956800d5243800e", repo.get("/lib/project.rb").id
    
    #####
    
    repo.branch = "gitgo"
    expected = {
      "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      :lib     => ["040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
    }
    assert_equal expected, repo.tree
  
    repo.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
    expected = {
      "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      "lib"    => {
        0 => "040000",
        "project.rb" => ["100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => ["100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4", :add],
        }
      }
    }
    assert_equal expected, repo.tree
  
    repo.rm("README")
    expected = {
      "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1", :rm],
      "lib"    => {
        0 => "040000",
        "project.rb" => ["100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => ["100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4", :add],
        }
      }
    }
    assert_equal expected, repo.tree
  
    expected = {
      "README" => :rm,
      "lib/project/utils.rb" => :add
    }
    assert_equal expected, repo.status
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
  
  def test_get_accepts_an_array_path
    tree = repo.get([])
    assert_equal ["comments", "issues", "pages", "users"], contents(tree)

    tree = repo.get([""])
    assert_equal ["comments", "issues", "pages", "users"], contents(tree)

    tree = repo.get(["pages"])
    assert_equal ["one", "one.txt"], contents(tree)

    tree = repo.get(["", "pages", ""])
    assert_equal ["one", "one.txt"], contents(tree)

    blob = repo.get(["pages", "one.txt"])
    assert_equal "one.txt", blob.name
    assert_equal %Q{--- 
author: user.one@email.com
date: 2009-09-09 09:00:00 -06:00
--- 
Page one}, blob.data

    assert_equal nil, repo.get(["non_existant"])
    assert_equal nil, repo.get(["pages", "non_existant.txt"])
    assert_equal nil, repo.get(["pages", "one.txt", "path_under_a_blob"])
  end
  
  def test_get_is_not_destructive_to_array_paths
    array = ["", "pages", ""]
    tree = repo.get(array)
    assert_equal ["", "pages", ""], array
    assert_equal ["one", "one.txt"], contents(tree)
  end
  
  #
  # AGET test
  #
  
  def test_AGET_returns_blob_or_tree_content
    assert_equal %Q{--- 
author: user.one@email.com
date: 2009-09-09 09:00:00 -06:00
--- 
Page one}, repo["/pages/one.txt"]

    assert_equal(["one.txt", "one"], repo["/pages"])
    assert_equal(nil, repo["/non_existant.txt"])
    assert_equal(nil, repo["/pages/one.txt/non_existant.txt"])
  end
  
  #
  # ASET test
  #
  
  def test_ASET_adds_blob_content
    repo["/pages/one.txt"] = "New content"
    repo.commit("added new content")
    
    assert_equal "New content", repo["/pages/one.txt"]
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
    
    assert_equal({
      "pages/a.txt"=>:add,
      "pages/a/b.txt"=>:add,
      "pages/a/c.txt"=>:add
    }, repo.status)
    
    repo.rm("pages/one", "pages/one.txt", "/pages/a/c.txt")
    
    assert_equal({
      "pages/a.txt"=>:add,
      "pages/a/b.txt"=>:add,
      "pages/a/c.txt"=>:rm,
      "pages/one.txt"=>:rm,
      "pages/one/two.txt"=>:rm
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
  
  #
  # checkout test
  #
  
  def test_checkout_checks_the_repo_out_into_a_gitgo_directory_under_gitdir
    assert !File.exists?(repo.work_path)
    
    repo.checkout

    assert File.exists?(repo.work_path)
    assert_equal %Q{--- 
author: user.one@email.com
date: 2009-09-09 09:00:00 -06:00
--- 
Page one}, File.read(repo.work_path("pages/one.txt"))
  end
  
  #
  # clone test
  #
  
  def test_clone_clones_a_repository
    a = Repo.init(method_root.path(:tmp, "a"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b"))
    b.add("b" => "b content").commit("added a file")
    
    assert_equal a.branch, b.branch
    assert_equal method_root.path(:tmp, "a/.git"), a.repo.path
    assert_equal method_root.path(:tmp, "b/.git"), b.repo.path
    
    assert_equal "a content", a["a"]
    assert_equal nil, a["b"]
    assert_equal "a content", b["a"]
    assert_equal "b content", b["b"]
  end
  
  def test_clone_clones_a_bare_repository
    a = Repo.init(method_root.path(:tmp, "a.git"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b.git"), :bare => true)
    b.add("b" => "b content").commit("added a file")

    assert_equal a.branch, b.branch
    assert_equal method_root.path(:tmp, "a.git"), a.repo.path
    assert_equal method_root.path(:tmp, "b.git"), b.repo.path
    
    assert_equal "a content", a["a"]
    assert_equal nil, a["b"]
    assert_equal "a content", b["a"]
    assert_equal "b content", b["b"]
  end
  
  #
  # pull test
  #
  
  def test_clone_pulls_from_origin
    a = Repo.init(method_root.path(:tmp, "a"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b"))
    assert_equal "a content", b["a"]
    
    a.add("a" => "A content").commit("updated file")
    assert_equal "a content", b["a"]

    b.pull
    assert_equal "A content", b["a"]
  end
  
  def test_bare_clone_pulls_from_origin
    a = Repo.init(method_root.path(:tmp, "a.git"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b.git"), :bare => true)
    assert_equal "a content", b["a"]
    
    a.add("a" => "A content").commit("updated file")
    assert_equal "a content", b["a"]
    
    b.pull
    assert_equal "A content", b["a"]
  end
end