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
      "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      "lib"    => {
        "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"]
      }
    }
    assert_equal expected, repo.tree
  
    repo.reset
    expected = {
      "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      :lib     => [:"040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
    }
    assert_equal expected, repo.tree
  
    repo.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
    expected = {
      "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
      "lib"    => {
        "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => [:"100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"]
        }
      }
    }
    assert_equal expected, repo.tree
  
    repo.rm("README")
    expected = {
      "lib"    => {
        "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
        "project" => {
          "utils.rb" => [:"100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"]
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
  # version test
  #
  
  def version_ok?(required, actual)
    (required <=> actual) <= 0
  end
  
  def test_version_documentation
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,2])
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,3])
    assert_equal false, version_ok?([1,6,4,2], [1,6,4,1])
  end
  
  def test_version_ok
    # equal
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,2])
    
    # last slot
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,3])
    assert_equal false, version_ok?([1,6,4,2], [1,6,4,1])
    
    # middle slot
    assert_equal true, version_ok?([1,6,4,2], [1,7,4,2])
    assert_equal false, version_ok?([1,6,4,2], [1,5,4,2])
    
    # unequal slots
    assert_equal true, version_ok?([1,6,4,2], [1,6,4,2,1])
    assert_equal false, version_ok?([1,6,4,2], [1,6])
    assert_equal true, version_ok?([1,6,4,2], [1,7])
  end
  
  def test_version_returns_an_array_of_integers
    version = repo.version
    assert_equal Array, version.class
    assert_equal true, version.all? {|item| item.kind_of?(Integer) }
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
    
    assert_equal ["one", "one.txt", "x", "x.txt"], repo[""].sort
    assert_equal ["one", "one.txt", "x", "x.txt"], repo["/"].sort
    assert_equal ["two", "two.txt"], repo["one"].sort
    assert_equal ["two", "two.txt"], repo["/one"].sort
    assert_equal ["two", "two.txt"], repo["/one/"].sort
    
    assert_equal "Contents of file ONE.", repo["one.txt"]
    assert_equal "Contents of file ONE.", repo["/one.txt"]
    assert_equal "Contents of file TWO.", repo["/one/two.txt"]
  
    assert_equal nil, repo["/non_existant"]
    assert_equal nil, repo["/one/non_existant.txt"]
    assert_equal nil, repo["/one/two.txt/path_under_a_blob"]
  end
  
  def test_AGET_accepts_array_paths
    setup_repo("simple.git")
  
    assert_equal ["one", "one.txt", "x", "x.txt"], repo[[]].sort
    assert_equal ["one", "one.txt", "x", "x.txt"], repo[[""]].sort
    assert_equal ["two", "two.txt"], repo[["one"]].sort
    assert_equal ["two", "two.txt"], repo[["", "one", ""]].sort
    assert_equal "Contents of file ONE.", repo[["", "one.txt"]]
    assert_equal "Contents of file TWO.", repo[["one", "two.txt"]]
  
    assert_equal nil, repo[["non_existant"]]
    assert_equal nil, repo[["one", "non_existant.txt"]]
    assert_equal nil, repo[["one", "two.txt", "path_under_a_blob"]]
  end
  
  def test_AGET_is_not_destructive_to_array_paths
    setup_repo("simple.git")
  
    array = ["", "one", ""]
    assert_equal ["two", "two.txt"], repo[array].sort
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
    assert_equal ["one", "one.txt", "x", "x.txt"], repo["/"].sort
    
    repo.checkout("diff")
    
    assert_equal "diff", repo.branch
    assert_equal ["alpha.txt", "one", "x", "x.txt"], repo["/"].sort
  end
  
  def test_checkout_checks_the_repo_out_into_work_tree_in_the_block
    setup_repo("simple.git")
    
    expected_work_tree = repo.path(Repo::WORK_TREE)
    assert !File.exists?(expected_work_tree)

    repo.checkout do |work_tree|
      assert_equal expected_work_tree, work_tree
      assert File.directory?(work_tree)
      assert_equal "Contents of file TWO.", File.read(File.join(work_tree, "/one/two.txt"))
    end
    
    assert !File.exists?(expected_work_tree)
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
  
  def test_clone_and_pull_in_a_custom_env
    FileUtils.mkdir_p(method_root[:tmp])
    
    git_dir = method_root.path(:tmp, "c.git")
    work_tree = method_root.path(:tmp, "d")
    index_file = method_root.path(:tmp, "e")
    `GIT_DIR='#{git_dir}' git init --bare`
    
    current_env = {}
    ENV.each_pair do |key, value|
      current_env[key] = value
    end
    
    begin
      ENV['GIT_DIR'] = git_dir
      ENV['GIT_WORK_TREE'] = work_tree
      ENV['GIT_INDEX_FILE'] = index_file
      
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
    ensure
      ENV.clear
      current_env.each_pair do |key, value|
        ENV[key] = value
      end
    end
  end
  
  #
  # stats test
  #
  
  def test_stats_returns_a_hash_of_repo_stats
    stats = repo.stats
    assert_equal Hash, stats.class
    assert stats.include?("size")
    assert stats.include?("count")
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
  
  def test_create_adds_doc_by_timestamp
    date = Time.local(2009, 9, 9)
    id = repo.create("content", 'date' => date)
    
    repo.commit("added a new doc")
    
    assert_equal [id], repo["2009/0909"]
  end
  
  def test_create_indexes_new_docs
    john = Grit::Actor.new("John Doe", "john.doe@email.com")
    jane = Grit::Actor.new("Jane Doe", "jane.doe@email.com")
    
    assert_equal [], repo.index('state', 'one')
    assert_equal [], repo.index('state', 'two')
    
    assert_equal [], repo.index('author', john.email)
    assert_equal [], repo.index('author', jane.email)
    
    a = repo.create("new content", "author" => john, "state" => "one")
    b = repo.create("new content", "author" => jane, "state" => "two")
    c = repo.create("new content", "author" => jane, "state" => "one")
    
    assert_equal [a,c].sort, repo.index('state', 'one').sort
    assert_equal [b],        repo.index('state', 'two')
    
    assert_equal [a],        repo.index('author', john.email)
    assert_equal [b,c].sort, repo.index('author', jane.email).sort
  end
  
  #
  # list test
  #
  
  def test_list_returns_a_list_of_indexes_when_no_key_is_specified
    assert_equal [], repo.list
    
    john = Grit::Actor.new("John Doe", "john.doe@email.com")
    repo.create("new content", "author" => john, "state" => "one")
    
    assert_equal ["author", "state"], repo.list.sort
  end
  
  def test_list_returns_a_list_of_index_values
    assert_equal [], repo.list('author')
    
    john = Grit::Actor.new("John Doe", "john.doe@email.com")
    jane = Grit::Actor.new("Jane Doe", "jane.doe@email.com")
    
    a = repo.create("new content", "author" => john)
    b = repo.create("new content", "author" => jane)
    c = repo.create("new content", "author" => jane)
    
    assert_equal [jane.email, john.email], repo.list('author').sort
  end
  
  #
  # update test
  #
  
  def test_update_updates_the_index
    john = Grit::Actor.new("John Doe", "john.doe@email.com")
    jane = Grit::Actor.new("Jane Doe", "jane.doe@email.com")
    
    a = repo.create("new content", "author" => john, "state" => "one")
    b = repo.create("new content", "author" => jane, "state" => "two")
    c = repo.create("new content", "author" => jane, "state" => "one")
   
    doc = repo.read(c).merge("state" => "one")
    d = repo.set(:blob, doc.to_s)
    
    assert_equal [a,c].sort, repo.index('state', 'one').sort
    assert_equal [b],        repo.index('state', 'two')
    
    assert_equal [a],        repo.index('author', john.email)
    assert_equal [b,c].sort, repo.index('author', jane.email).sort
    
    repo.update(b, doc)
    
    assert_equal [a,c,d].sort, repo.index('state', 'one').sort
    assert_equal [],           repo.index('state', 'two')
    
    assert_equal [a],        repo.index('author', john.email)
    assert_equal [c,d].sort, repo.index('author', jane.email)
  end
  
  #
  # destroy test
  #
  
  def test_destroy_removes_the_document
    date = Time.local(2009, 9, 9)
    id = repo.create("content", 'date' => date)
    repo.commit("added a new doc")
    
    repo.destroy(id)
    repo.commit("removed the new doc")
    
    assert_equal [], repo["2009/0909"]
  end
  
  def test_destroy_removes_the_doc_from_the_index
    john = Grit::Actor.new("John Doe", "john.doe@email.com")
    jane = Grit::Actor.new("Jane Doe", "jane.doe@email.com")
    
    a = repo.create("new content", "author" => john, "state" => "one")
    b = repo.create("new content", "author" => jane, "state" => "two")
    c = repo.create("new content", "author" => jane, "state" => "one")
    
    assert_equal [a,c].sort, repo.index('state', 'one').sort
    assert_equal [b],        repo.index('state', 'two')
    
    assert_equal [a],        repo.index('author', john.email)
    assert_equal [b,c].sort, repo.index('author', jane.email).sort
    
    repo.destroy(b)
    
    assert_equal [a,c].sort, repo.index('state', 'one').sort
    assert_equal [],         repo.index('state', 'two')
    
    assert_equal [a],        repo.index('author', john.email)
    assert_equal [c],        repo.index('author', jane.email)
  end
  
  #
  # cache test
  #
  
  def test_cache_documentation
    repo = Repo.new
    id = repo.create("new doc")
  
    docs = repo.cache
    assert_equal "new doc", docs[id].content
    assert_equal true, docs[id].equal?(docs[id])
  
    alts = repo.cache
    assert_equal "new doc", alts[id].content
    assert_equal false, alts[id].equal?(docs[id])
  end
  
  #
  # each test
  #
  
  def test_each_yields_each_doc_to_the_block_reverse_ordered_by_date
    a = repo.create("a", 'date' => Time.utc(2009, 9, 11))
    b = repo.create("d", 'date' => Time.utc(2009, 9, 10))
    c = repo.create("c", 'date' => Time.utc(2009, 9, 9))
    
    repo.commit("added docs")
    
    results = []
    repo.each {|doc| results << doc }
    assert_equal [a, b, c], results
  end
  
  def test_each_does_not_yield_doc_like_entries_in_repo
    a = repo.create("a", 'date' => Time.utc(2009, 9, 11))
    b = repo.create("d", 'date' => Time.utc(2009, 9, 10))
    c = repo.create("c", 'date' => Time.utc(2009, 9, 9))
    
    repo.add(
      "year/mmdd" => "skipped",
      "00/0000" => "skipped",
      "0000/00" => "skipped"
    )
    repo.commit("added docs and other files")
    
    results = []
    repo.each {|doc| results << doc }
    assert_equal [a, b, c], results
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
  # link test
  #

  def test_link_links_the_parent_sha_to_the_empty_sha_by_child
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")

    repo.link(a, b).commit("linked a file")
    assert_equal "", repo["#{a[0,2]}/#{a[2,38]}/#{b}"]
  end

  def test_link_links_to_ref_if_specified
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")
    c = repo.set("blob", "c")

    repo.link(a, b, :ref => c).commit("linked a file")
    assert_equal c, repo["#{a[0,2]}/#{a[2,38]}/#{b}"]
  end

  def test_link_nests_link_under_dir_if_specified
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")

    repo.link(a, b, :dir => "path/to/dir").commit("linked a file")
    assert_equal "", repo["path/to/dir/#{a[0,2]}/#{a[2,38]}/#{b}"]
  end
  
  #
  # ref test
  #

  def test_ref_returns_the_ref_attribute_in_a_link
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")
    c = repo.set("blob", "c")

    repo.link(a, b, :ref => c).commit("linked a file")
    assert_equal c, repo.ref(a, b)

    repo.link(a, c).commit("linked a file")
    assert_equal "", repo.ref(a, c)
  end

  def test_ref_works_with_link_options
    a = repo.set("blob", "a")
    b = repo.set("blob", "b")
    c = repo.set("blob", "c")

    repo.link(a, b, :ref => c, :dir => "path/to/dir").commit("linked a file")
    assert_equal c, repo.ref(a, b, :dir => "path/to/dir")

    repo.link(a, c, :dir => "path/to/dir").commit("linked a file")
    assert_equal "", repo.ref(a, c, :dir => "path/to/dir")
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

  def test_parents_only_searches_trees_in_the_ab_xyz_format
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")

    repo.link(a, c)
    repo.add("abc/#{b[2,38]}/#{c}" => "not ab")
    repo.add("#{b[0,2]}/xy/#{c}" => "not xyx")
    repo.commit("created links and skipped 'links'")

    assert_equal [a], repo.parents(c)
    assert_equal [a[0,2], "abc", b[0,2]].sort, repo["/"].sort
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

  def test_children_returns_a_hash_of_children_if_recursive_is_specified
    a = repo.set("blob", "A")
    b = repo.set("blob", "B")
    c = repo.set("blob", "C")

    repo.link(a, b).link(b, c).commit("created recursive links")

    assert_equal [b], repo.children(a)
    assert_equal({a => [b], b => [c], c => []}, repo.children(a, :recursive => true))
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

    result = repo.children(a, :recursive => true)
    result.each_value {|value| value.sort! }
    assert_equal({
      a => [b, c].sort,
      b => [d],
      c => [d],
      d => []
    }, result)
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

    assert_equal [b, c].sort, repo.children(a).sort
    assert_equal [], repo.children(b)
    assert_equal [a], repo.parents(c)

    repo.unlink(b, c)
    repo.unlink(nil, c)
    repo.unlink(b, nil)

    assert_equal [b, c].sort, repo.children(a).sort
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
  # integrity tests
  #
  
  def test_repo_is_ok_after_create_link_and_commit
    @repo = Repo.init(method_root[:tmp])
    
    a = repo.create("new content a")
    b = repo.create("new content b")
    c = repo.create("new content c")
    
    repo.link(a,b).link(b,c)
    repo.commit("new commit")
    
    assert_equal ["notice: HEAD points to an unborn branch (master)"], repo.fsck
  end
  
end