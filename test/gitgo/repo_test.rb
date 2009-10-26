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
    repo = Repo.init(method_root.path(:tmp, "example"), :author => "John Doe <jdoe@example.com>")
    repo.add(
      "README" => "New Project",
      "lib/project.rb" => "module Project\nend"
    ).commit("added files")
    
    expected = {
      "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      :lib     => ["040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
    }
    assert_equal expected, repo.tree
  
    repo.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
    expected = {
      "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      "lib"    => {
        "project.rb" => ["100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => ["100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"],
        }
      }
    }
    assert_equal expected, repo.tree
  
    repo.rm("README")
    expected = {
      "lib"    => {
        "project.rb" => ["100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => ["100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"],
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
    assert_equal git_path, repo.grit.path
    
    repo.add("path" => "content").commit("initial commit")
    
    assert_equal "initial commit", repo.current.message
    assert_equal "content", repo["path"]
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
    assert_equal "content", repo["path"]
  end
  
  #
  # author test
  #
  
  def test_author_determines_a_default_author_from_the_repo_config
    setup_repo("simple.git")
    
    author = repo.author
    assert_equal "John Doe", author.name
    assert_equal "john.doe@email.com", author.email
  end
  
  #
  # get test
  #
  
  def test_get_returns_the_specified_object
    setup_repo("simple.git")
    
    blob = repo.get(:blob, "32f1859c0aaf1394789093c952f2b03ab04a1aad")
    assert_equal Grit::Blob, blob.class
    assert_equal "Contents of file ONE.", blob.data
    
    tree = repo.get(:tree, "09aa1d0c0d69df84464b72623628acf5c63c79f0")
    assert_equal Grit::Tree, tree.class
    assert_equal ["two", "two.txt"], tree.contents.collect {|obj| obj.name }.sort
  end

  #
  # set test
  #
  
  def test_set_writes_an_object_of_the_specified_type_to_repo
    id = repo.set(:blob, "new content")
    assert_equal "new content", repo.get(:blob, id).data
  end
  
  #
  # AGET test
  #

  def test_AGET_returns_the_contents_of_the_object_at_path
    setup_repo("simple.git")
    
    assert_equal ["one", "one.txt", "x", "x.txt"], repo[""]
    assert_equal ["one", "one.txt", "x", "x.txt"], repo["/"]
    assert_equal ["two", "two.txt"], repo["one"]
    assert_equal ["two", "two.txt"], repo["/one"]
    assert_equal ["two", "two.txt"], repo["/one/"]
    
    assert_equal "Contents of file ONE.", repo["one.txt"]
    assert_equal "Contents of file ONE.", repo["/one.txt"]
    assert_equal "Contents of file TWO.", repo["/one/two.txt"]
  
    assert_equal nil, repo["/non_existant"]
    assert_equal nil, repo["/one/non_existant.txt"]
    assert_equal nil, repo["/one/two.txt/path_under_a_blob"]
  end
  
  def test_AGET_accepts_array_paths
    setup_repo("simple.git")
  
    assert_equal ["one", "one.txt", "x", "x.txt"], repo[[]]
    assert_equal ["one", "one.txt", "x", "x.txt"], repo[[""]]
    assert_equal ["two", "two.txt"], repo[["one"]]
    assert_equal ["two", "two.txt"], repo[["", "one", ""]]
    assert_equal "Contents of file ONE.", repo[["", "one.txt"]]
    assert_equal "Contents of file TWO.", repo[["one", "two.txt"]]
  
    assert_equal nil, repo[["non_existant"]]
    assert_equal nil, repo[["one", "non_existant.txt"]]
    assert_equal nil, repo[["one", "two.txt", "path_under_a_blob"]]
  end
  
  def test_AGET_is_not_destructive_to_array_paths
    setup_repo("simple.git")
  
    array = ["", "one", ""]
    assert_equal ["two", "two.txt"], repo[array]
    assert_equal ["", "one", ""], array
  end
  
  def test_AGET_returns_committed_content_if_specified
    setup_repo("simple.git")
  
    assert_equal "Contents of file ONE.", repo["one.txt"]
    repo.tree["one.txt"] = [Repo::DEFAULT_BLOB_MODE, repo.set(:blob, "new content")]
    
    assert_equal "new content", repo["one.txt"]
    assert_equal "Contents of file ONE.", repo["one.txt", true]
  end
  
  #
  # ASET test
  #

  def test_ASET_adds_blob_content
    assert_equal nil, repo["/a/b.txt"]
    repo["/a/b.txt"] = "new content"
    assert_equal "new content", repo["/a/b.txt"]
  end
  
  def test_new_blob_content_is_not_committed_automatically
    assert_equal nil, repo["/a/b.txt", true]
    repo["/a/b.txt"] = "new content"
    assert_equal nil, repo["/a/b.txt", true]
  end
    
  #
  # link test
  #
  
  def test_link_links_the_parent_sha_to_the_empty_sha_by_child
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")
  
    repo.link(a, b).commit("linked a file")
    assert_equal "", repo["#{a[0,2]}/#{a[2,38]}/#{b}"]
  end
  
  def test_link_nests_link_under_dir_if_specified
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")
  
    repo.link(a, b, :dir => "path/to/dir").commit("linked a file")
    assert_equal "", repo["path/to/dir/#{a[0,2]}/#{a[2,38]}/#{b}"]
  end

  #
  # parents test
  #

  def test_parents_returns_array_of_parents_linking_to_child
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, c).link(b, c).commit("created links")
    
    assert_equal [a, b].sort, repo.parents(c).sort
    assert_equal [], repo.parents(b)
  end
  
  def test_parents_returns_array_of_parents_linking_to_child_under_dir_if_specified
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, c, :dir => "one").link(b, c, :dir => "two").commit("created links")
    
    assert_equal [a], repo.parents(c, :dir => "one")
    assert_equal [b], repo.parents(c, :dir => "two")
  end
  
  #
  # children test
  #

  def test_children_returns_array_of_linked_children
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, b).link(a, c).commit("created links")
    
    assert_equal [b, c].sort, repo.children(a).sort
    assert_equal [], repo.children(b)
  end
  
  def test_children_returns_array_of_linked_children_under_dir_if_specified
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, b, :dir => "one").link(a, c, :dir => "two").commit("created links")
    
    assert_equal [b], repo.children(a, :dir => "one")
    assert_equal [c], repo.children(a, :dir => "two")
  end

  def test_children_returns_a_nested_hash_of_children_if_recursive_is_specified
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, b).link(b, c).commit("created recursive links")
    
    assert_equal [b], repo.children(a)
    assert_equal({b => {c => {}}}, repo.children(a, :recursive => true))
  end

  def test_recursive_children_detects_circular_linkage
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")

    repo.link(a, b).link(b, c).link(c, a).commit("created a circular linkage")

    err = assert_raises(RuntimeError) { repo.children(a, :recursive => true) }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{c}
  #{a}
}, err.message
  end

  def test_recursive_children_allows_two_threads_to_link_the_same_commit
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    d = repo.set("blob", "D")

    repo.link(a, b)
    repo.link(b, d)

    repo.link(a, c)
    repo.link(c, d)

    repo.commit("linked to the same commit on two threads")

    assert_equal({
      b => {d => {}},
      c => {d => {}}
    }, repo.children(a, :recursive => true))
  end

  #
  # unlink test
  #

  def test_unlink_removes_the_parent_child_linkage
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, b).link(b, c).commit("created recursive links")
    
    assert_equal [b], repo.children(a)
    assert_equal [c], repo.children(b)
    
    repo.unlink(a, b).commit("unlinked a, b")

    assert_equal [], repo.children(a)
    assert_equal [c], repo.children(b)
  end

  def test_unlink_reursively_removes_children_if_specified
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, b).link(b, c).commit("created recursive links")
    
    assert_equal [b], repo.children(a)
    assert_equal [c], repo.children(b)
    
    repo.unlink(a, b, :recursive => true).commit("recursively unlinked a, b")

    assert_equal [], repo.children(a)
    assert_equal [], repo.children(b)
  end
  
  def test_unlink_removes_children_under_dir_if_specified
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    d = repo.set("blob", "C")
    e = repo.set("blob", "C")
    
    repo.link(a, b, :dir => "one").link(b, c, :dir => "one")
    repo.link(a, d, :dir => "two").link(d, e, :dir => "two")
    
    repo.commit("created recursive links under dir")
    
    assert_equal [b], repo.children(a, :dir => "one")
    assert_equal [c], repo.children(b, :dir => "one")
    assert_equal [d], repo.children(a, :dir => "two")
    assert_equal [e], repo.children(d, :dir => "two")
    
    repo.unlink(a, d, :dir => "two", :recursive => true).commit("recursively unlinked a under dir")

    assert_equal [b], repo.children(a, :dir => "one")
    assert_equal [c], repo.children(b, :dir => "one")
    assert_equal [], repo.children(a, :dir => "two")
    assert_equal [], repo.children(d, :dir => "two")
  end
  
  def test_unlink_quietly_does_nothing_for_unlinked_or_missing_parent_or_child
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")
    
    repo.link(a, b).link(a, c).commit("created recursive links")
    
    assert_equal [b, c], repo.children(a)
    assert_equal [], repo.children(b)
    assert_equal [a], repo.parents(c)
    
    repo.unlink(b, c)
    repo.unlink(nil, c)
    repo.unlink(b, nil)
    
    assert_equal [b, c], repo.children(a)
    assert_equal [], repo.children(b)
    assert_equal [a], repo.parents(c)
  end
  
  def test_recursive_unlink_removes_circular_linkages
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")

    repo.link(a, b).link(b, c).link(c, a).commit("created a circular linkage")

    err = assert_raises(RuntimeError) { repo.children(a, :recursive => true) }
    repo.unlink(a, b, :recursive => true).commit("unlinked links")
    
    assert_equal [], repo.children(a)
    assert_equal [], repo.children(b)
    assert_equal [], repo.children(c)
  end
  
  #
  # create test
  #
  
  def test_create_adds_a_new_document_to_the_repo_and_returns_the_new_doc_id
    setup_repo("simple.git") # to setup a default author
    
    sha = repo.create("new content")
    doc = repo.read(sha)
    
    assert_equal "new content", doc.content
    assert_equal "John Doe", doc.author.name
    assert_equal "john.doe@email.com", doc.author.email
    assert_equal Time.now.strftime("%Y/%m/%d"), doc.date.strftime("%Y/%m/%d")
  end
  
  def test_create_respects_any_atttributes_specified_with_the_document
    sha = repo.create("new content", "author" => Grit::Actor.new("New User", "new.user@email.com"), "key" => "value")
    doc = repo.read(sha)
    
    assert_equal "new content", doc.content
    assert_equal "New User", doc.author.name
    assert_equal "new.user@email.com", doc.author.email
    assert_equal "value", doc.attributes["key"]
  end
  
  def test_create_adds_doc_sha_to_timestamp_and_author_index
    date = Time.utc(2009, 9, 9)
    author = Grit::Actor.new('John Doe', 'john.doe@email.com')
    id = repo.create("content", 'author' => author, 'date' => date)
    
    repo.commit("added a new doc")
    
    assert_equal [id], repo["idx/2009/0909"]
    assert_equal id, repo["idx/john.doe@email.com/#{date.to_i}#{date.usec.to_s[0,2]}"]
  end
  
  #
  # destroy test
  #
  
  def test_destroy_removes_the_document_and_associated_indicies
    date = Time.utc(2009, 9, 9)
    author = Grit::Actor.new('John Doe', 'john.doe@email.com')
    
    id = repo.create("content", 'author' => author, 'date' => date)
    repo.commit("added a new doc")
    
    repo.destroy(id)
    repo.commit("removed the new doc")
    
    assert_equal [], repo["idx/2009/0909"]
    assert_equal nil, repo["idx/john.doe@email.com/#{date.to_i}#{date.usec.to_s[0,2]}"]
  end
  
  #
  # timeline test
  #
  
  def test_timeline_returns_the_most_recently_added_docs
    a = repo.create("a", 'date' => Time.utc(2009, 9, 11))
    d = repo.create("d", 'date' => Time.utc(2009, 9, 10))
    c = repo.create("c", 'date' => Time.utc(2009, 9, 9))
    
    b = repo.create("b", 'date' => Time.utc(2008, 9, 10))
    e = repo.create("e", 'date' => Time.utc(2008, 9, 9))
    
    repo.commit("added docs")
    
    assert_equal [a, d, c, b, e], repo.timeline
    assert_equal [ d, c, b], repo.timeline(:n => 3, :offset => 1)
  end
  
  #
  # activity test
  #
  
  def test_activity_returns_activity_by_the_author_ordered_by_date
    john = Grit::Actor.new('John Doe', 'john.doe@email.com')
    jane = Grit::Actor.new('Jane Doe', 'jane.doe@email.com')
    
    a = repo.create("a", 'author' => john, 'date' => Time.utc(2009, 9, 11))
    d = repo.create("d", 'author' => jane, 'date' => Time.utc(2009, 9, 10))
    c = repo.create("c", 'author' => john, 'date' => Time.utc(2009, 9, 9))
    
    b = repo.create("b", 'author' => john, 'date' => Time.utc(2008, 9, 10))
    e = repo.create("e", 'author' => jane, 'date' => Time.utc(2008, 9, 9))
    
    repo.commit("added docs")
    
    assert_equal [a,c,b], repo.activity(john)
    assert_equal [d,e], repo.activity(jane)
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
      "one.txt" => :rm,
      "one/two.txt" => :rm,
      "one/two/three.txt"=>:rm
    }, repo.status)
  end
  
  #
  # checkout test
  #
  
  def test_checkout_resets_branch_if_specified
    setup_repo("simple.git")
    
    assert_equal "master", repo.branch
    assert_equal ["one", "one.txt", "x", "x.txt"], repo["/"]
    
    repo.checkout("diff")
    
    assert_equal "diff", repo.branch
    assert_equal ["alpha.txt", "one", "x", "x.txt"], repo["/"]
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
    assert_equal method_root.path(:tmp, "a.git"), a.path
    assert_equal method_root.path(:tmp, "b.git"), b.path
    
    assert_equal "a content", a["a"]
    assert_equal nil, a["b"]
    assert_equal "a content", b["a"]
    assert_equal "b content", b["b"]
  end
  
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