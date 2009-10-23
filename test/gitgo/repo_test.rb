require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class RepoTest < Test::Unit::TestCase
  include RepoTestHelper
  Repo = Gitgo::Repo
  
  attr_writer :repo
  
  def setup
    super
    @repo = nil
  end
  
  def repo
    @repo ||= Repo.init(method_root[:tmp], :bare => true)
  end
  
  def setup_repo(repo)
    @repo = Repo.new(super(repo), :branch => "master")
  end
  
  
  #
  # documentation test
  #
  
  def test_repo_documentation
    repo = Repo.init(method_root.path(:tmp, "example"), :user => "John Doe <jdoe@example.com>")
    repo.add(
      "README" => "New Project",
      "lib/project.rb" => "module Project\nend"
    ).commit("added files")
    
    expected = {
      "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      :lib     => ["040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
    }
    assert_equal expected, repo.index
  
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
    assert_equal expected, repo.index
  
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
    assert_equal expected, repo.index
  
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
    assert_equal git_path, repo.grit.path
    
    repo.add("path" => "content").commit("initial commit")
    
    assert_equal "initial commit", repo.current.message
    assert_equal "content", repo.get("path").data
  end
  
  def test_init_initializes_bare_repo_if_specified
    path = method_root[:tmp]
    assert !File.exists?(path)
    
    repo = Repo.init(path, :is_bare => true)
    
    assert !File.exists?(method_root.path(:tmp, ".git"))
    assert File.exists?(path)
    assert_equal path, repo.grit.path
    
    repo.add("path" => "content").commit("initial commit")
    
    assert_equal "initial commit", repo.current.message
    assert_equal "content", repo.get("path").data
  end
  
  #
  # user test
  #
  
  def test_user_determines_a_default_user_from_the_repo_config
    setup_repo("simple.git")
    
    user = repo.user
    assert_equal "John Doe", user.name
    assert_equal "john.doe@email.com", user.email
  end
  
  #
  # get test
  #

  def contents(tree)
    tree.contents.collect {|obj| obj.name }.sort
  end

  def test_get_returns_an_object_corresponding_to_the_path
    setup_repo("simple.git")
    
    tree = repo.get("")
    assert_equal ["one", "one.txt", "x", "x.txt"], contents(tree)
    
    tree = repo.get("/")
    assert_equal ["one", "one.txt", "x", "x.txt"], contents(tree)

    tree = repo.get("one")
    assert_equal ["two", "two.txt"], contents(tree)

    tree = repo.get("/one")
    assert_equal ["two", "two.txt"], contents(tree)
    
    tree = repo.get("/one/")
    assert_equal ["two", "two.txt"], contents(tree)
    
    blob = repo.get("/one/two.txt")
    assert_equal "two.txt", blob.name
    assert_equal "Contents of file TWO.", blob.data

    assert_equal nil, repo.get("/non_existant")
    assert_equal nil, repo.get("/one/non_existant.txt")
    assert_equal nil, repo.get("/one/two.txt/path_under_a_blob")
  end
  
  def test_get_accepts_an_array_path
    setup_repo("simple.git")
    
    tree = repo.get([])
    assert_equal ["one", "one.txt", "x", "x.txt"], contents(tree)
  
    tree = repo.get([""])
    assert_equal ["one", "one.txt", "x", "x.txt"], contents(tree)
  
    tree = repo.get(["one"])
    assert_equal ["two", "two.txt"], contents(tree)
  
    tree = repo.get(["", "one", ""])
    assert_equal ["two", "two.txt"], contents(tree)
  
    blob = repo.get(["one", "two.txt"])
    assert_equal "two.txt", blob.name
    assert_equal "Contents of file TWO.", blob.data
  
    assert_equal nil, repo.get(["non_existant"])
    assert_equal nil, repo.get(["one", "non_existant.txt"])
    assert_equal nil, repo.get(["one", "two.txt", "path_under_a_blob"])
  end
  
  def test_get_is_not_destructive_to_array_paths
    setup_repo("simple.git")
    
    array = ["", "one", ""]
    tree = repo.get(array)
    
    assert_equal ["", "one", ""], array
    assert_equal ["two", "two.txt"], contents(tree)
  end
  
  #
  # AGET test
  #

  def test_AGET_returns_blob_or_tree_content
    setup_repo("simple.git")
    
    assert_equal "Contents of file TWO.", repo["/one/two.txt"]
    assert_equal(["two.txt", "two"], repo["/one"])
    
    assert_equal(nil, repo["/non_existant.txt"])
    assert_equal(nil, repo["/one/two.txt/non_existant.txt"])
  end

  #
  # ASET test
  #

  def test_ASET_adds_blob_content
    assert_equal nil, repo["/a/b.txt"]
    
    repo["/a/b.txt"] = "new content"
    repo.commit("added new content")

    assert_equal "new content", repo["/a/b.txt"]
  end
  
  #
  # create test
  #
  
  def test_create_adds_a_new_document_to_the_repo_and_returns_the_new_doc_id
    setup_repo("simple.git") # to setup a default user
    
    sha = repo.create("new content")
    doc = repo.doc(sha)
    
    assert_equal "new content", doc.content
    assert_equal "John Doe", doc.author.name
    assert_equal "john.doe@email.com", doc.author.email
    assert_equal Time.now.strftime("%Y/%m/%d"), doc.timestamp
  end
  
  def test_create_respects_any_atttributes_specified_with_the_document
    sha = repo.create("new content", "author" => Grit::Actor.new("New User", "new.user@email.com"), "key" => "value")
    doc = repo.doc(sha)
    
    assert_equal "new content", doc.content
    assert_equal "New User", doc.author.name
    assert_equal "new.user@email.com", doc.author.email
    assert_equal "value", doc.attributes["key"]
  end
  
  #
  # link test
  #
  
  def test_link_links_the_parent_sha_to_the_child_sha
    parent = repo.write("blob", "parent content")
    child = repo.write("blob", "child content")
  
    repo.link(parent, child).commit("linked a file")
    assert_equal "child content", repo["#{parent[0,2]}/#{parent[2,38]}/#{child}"]
  
    repo.link(parent, child, :mode => "100644", :as => child + ".ext").commit("linked a file with an extension")
    assert_equal "child content", repo["#{parent[0,2]}/#{parent[2,38]}/#{child}.ext"]
  end

  #
  # links test
  #

  def test_links_returns_array_of_linked_children
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    
    repo.link(a, b).link(a, c).commit("created links")
    
    assert_equal [b, c].sort, repo.links(a).sort
    assert_equal [], repo.links(b)
  end

  def test_links_returns_a_nested_hash_of_children_if_recursive_is_specified
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    
    repo.link(a, b).link(b, c).commit("created recursive links")
    
    assert_equal [b], repo.links(a)
    assert_equal({b => {c => {}}}, repo.links(a, :recursive => true))
  end

  def test_recursive_links_detects_circular_linkage
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")

    repo.link(a, b).link(b, c).link(c, a).commit("created a circular linkage")

    err = assert_raises(RuntimeError) { repo.links(a, :recursive => true) }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{c}
  #{a}
}, err.message
  end

  def test_recursive_links_allows_two_threads_to_link_the_same_commit
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    d = repo.write("blob", "D")

    repo.link(a, b)
    repo.link(b, d)

    repo.link(a, c)
    repo.link(c, d)

    repo.commit("linked to the same commit on two threads")

    assert_equal({
      b => {d => {}},
      c => {d => {}}
    }, repo.links(a, :recursive => true))
  end

  #
  # unlink test
  #

  def test_unlink_removes_the_parent_child_linkage
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    
    repo.link(a, b).link(b, c).commit("created recursive links")
    
    assert_equal [b], repo.links(a)
    assert_equal [c], repo.links(b)
    
    repo.unlink(a, b).commit("unlinked a, b")

    assert_equal [], repo.links(a)
    assert_equal [c], repo.links(b)
  end

  def test_unlink_reursively_removes_children_if_specified
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    
    repo.link(a, b).link(b, c).commit("created recursive links")
    
    assert_equal [b], repo.links(a)
    assert_equal [c], repo.links(b)
    
    repo.unlink(a, b, :recursive => true).commit("recursively unlinked a, b")

    assert_equal [], repo.links(a)
    assert_equal [], repo.links(b)
  end
  
  def test_recursive_unlink_removes_circular_linkages
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")

    repo.link(a, b).link(b, c).link(c, a).commit("created a circular linkage")

    err = assert_raises(RuntimeError) { repo.links(a, :recursive => true) }
    repo.unlink(a, b, :recursive => true).commit("unlinked links")
    
    assert_equal [], repo.links(a)
    assert_equal [], repo.links(b)
    assert_equal [], repo.links(c)
  end
  
  #
  # register test
  #

  def test_register_adds_the_sha_to_the_type_directory
    issue = repo.write("blob", "new issue")

    repo.register("issues", issue).commit("added an issue")
    assert_equal "new issue", repo["issues/#{issue[0,2]}/#{issue[2,38]}"]
  end

  def test_register_can_register_new_types
    thing = repo.write("blob", "new thing")

    repo.register("things", thing).commit("added a thing")
    assert_equal "new thing", repo["things/#{thing[0,2]}/#{thing[2,38]}"]
  end

  #
  # registry test
  #

  def test_registry_returns_array_of_registered_shas
    assert_equal [], repo.registry("type")

    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    
    repo.register("type", a).register("type", b).commit("registered shas")
    
    assert_equal [a, b].sort, repo.registry("type").sort
  end

  #
  # unregister test
  #

  def test_unregister_removes_registered_shas
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    
    repo.register("type", a).register("type", b).link(b, c).commit("registered shas")
    
    assert_equal [a, b].sort, repo.registry("type").sort
    assert_equal [c], repo.links(b)
    
    repo.unregister("type", b).commit("unregistered b")
  
    assert_equal [a], repo.registry("type")
    assert_equal [c], repo.links(b)
  end
  
  def test_unregister_reursively_removes_linked_children_if_specified
    a = repo.write("blob", "A")
    b = repo.write("blob", "B")
    c = repo.write("blob", "C")
    
    repo.register("type", a).register("type", b).link(b, c).commit("registered shas")
    
    assert_equal [a, b].sort, repo.registry("type").sort
    assert_equal [c], repo.links(b)
    
    repo.unregister("type", b, :recursive => true).commit("unregistered b")
  
    assert_equal [a], repo.registry("type")
    assert_equal [], repo.links(b)
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
  
  def test_status_returns_hash_of_staged_changes
    setup_repo("simple.git")
    
    assert_equal({}, repo.status)
    
    repo.add(
      "a.txt" => "file a content",
      "a/b.txt" => "file b content",
      "a/c.txt" => "file c content"
    )
    
    assert_equal({
      "a.txt" => :add,
      "a/b.txt" => :add,
      "a/c.txt" => :add
    }, repo.status)
    
    repo.rm("one", "one.txt", "a/c.txt")
    
    assert_equal({
      "a.txt" => :add,
      "a/b.txt" => :add,
      "a/c.txt" => :rm,
      "one.txt" => :rm,
      "one/two.txt" => :rm,
      "one/two/three.txt"=>:rm
    }, repo.status)
  end
  
  #
  # add test
  #
  
  def test_add_adds_the_specified_contents
    repo.add(
      "a.txt" => "file a content",
      "/a/b.txt" => "file b content",
      "a/c.txt" => "file c content"
    )
    
    # check the trees and commit have not been made
    assert_equal nil, repo.get("/")
    assert_equal nil, repo.get("a")
    assert_equal nil, repo.get("a.txt")
    
    repo.commit("added files")
    
    # now after the commit check everything is pulld
    blob = repo.get("/a.txt")
    assert_equal "file a content", blob.data
    
    blob = repo.get("/a/b.txt")
    assert_equal "file b content", blob.data
    
    blob = repo.get("/a/c.txt")
    assert_equal "file c content", blob.data
    
    tree = repo.get("/")
    assert_equal ["a", "a.txt"], contents(tree)
    
    tree = repo.get("/a")
    assert_equal ["b.txt", "c.txt"], contents(tree)
  end
  
  #
  # checkout test
  #
  
  def test_checkout_resets_branch_if_specified
    setup_repo("simple.git")
    
    assert_equal "master", repo.branch
    assert_equal ["one", "one.txt", "x", "x.txt"], contents(repo.get("/"))
    
    repo.checkout("diff")
    
    assert_equal "diff", repo.branch
    assert_equal ["alpha.txt", "one", "x", "x.txt"], contents(repo.get("/"))
  end
  
  def test_checkout_checks_the_repo_out_into_path
    setup_repo("simple.git")
    
    path = method_root.path(:tmp, "work")
    assert !File.exists?(path)

    repo.checkout(nil, path)

    assert File.directory?(path)
    assert_equal "Contents of file TWO.", File.read(method_root.path(:tmp, "work/one/two.txt"))
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
    assert_equal method_root.path(:tmp, "a/.git"), a.path
    assert_equal method_root.path(:tmp, "b/.git"), b.path
    
    assert_equal "a content", a.get("a").data
    assert_equal nil, a.get("b")
    assert_equal "a content", b.get("a").data
    assert_equal "b content", b.get("b").data
  end
  
  def test_clone_clones_a_bare_repository
    a = Repo.init(method_root.path(:tmp, "a.git"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b.git"), :bare => true)
    b.add("b" => "b content").commit("added a file")

    assert_equal a.branch, b.branch
    assert_equal method_root.path(:tmp, "a.git"), a.path
    assert_equal method_root.path(:tmp, "b.git"), b.path
    
    assert_equal "a content", a.get("a").data
    assert_equal nil, a.get("b")
    assert_equal "a content", b.get("a").data
    assert_equal "b content", b.get("b").data
  end
  
  def test_clone_pulls_from_origin
    a = Repo.init(method_root.path(:tmp, "a"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b"))
    assert_equal "a content", b.get("a").data
    
    a.add("a" => "A content").commit("pulld file")
    assert_equal "a content", b.get("a").data

    b.pull
    assert_equal "A content", b.get("a").data
  end
  
  def test_bare_clone_pulls_from_origin
    a = Repo.init(method_root.path(:tmp, "a.git"))
    a.add("a" => "a content").commit("added a file")
    
    b = a.clone(method_root.path(:tmp, "b.git"), :bare => true)
    assert_equal "a content", b.get("a").data
    
    a.add("a" => "A content").commit("pulld file")
    assert_equal "a content", b.get("a").data
    
    b.pull
    assert_equal "A content", b.get("a").data
  end
end