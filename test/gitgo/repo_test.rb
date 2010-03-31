require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class RepoTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  
  attr_accessor :repo
  
  def setup
    super
    @repo = Repo.new(Repo::PATH => method_root.path(:repo))
  end
  
  def git
    repo.git
  end
  
  def idx
    repo.idx
  end
  
  def serialize(attrs)
    JSON.generate(attrs)
  end
  
  def create_nodes(*contents)
    date = Time.now
    contents.collect do |content|
      date += 1
      repo.store("content" => content, "date" => date)
    end
  end
  
  #
  # Repo.with_env test
  #
  
  def test_with_env_sets_env_during_block
    Repo.with_env(:a) do
      assert_equal :a, Repo.env
      
      Repo.with_env(:z) do
        assert_equal :z, Repo.env
      end
      
      assert_equal :a, Repo.env
    end
  end
  
  #
  # Repo.env test
  #
  
  def test_env_returns_thread_specific_env
    current = Thread.current[Repo::ENVIRONMENT]
    begin
      Thread.current[Repo::ENVIRONMENT] = :env
      assert_equal :env, Repo.env
    ensure
      Thread.current[Repo::ENVIRONMENT] = current
    end
  end
  
  def test_env_raises_error_when_no_env_is_in_scope
    current = Thread.current[Repo::ENVIRONMENT]
    begin
      Thread.current[Repo::ENVIRONMENT] = nil
      
      err = assert_raises(RuntimeError) { Repo.env }
      assert_equal "no env in scope", err.message
    ensure
      Thread.current[Repo::ENVIRONMENT] = current
    end
  end
  
  #
  # Repo.current test
  #
  
  def test_current_returns_repo_set_in_env
    Repo.with_env(Repo::REPO => :repo) do
      assert_equal :repo, Repo.current
    end
  end
  
  def test_current_auto_initializes_to_env
    Repo.with_env({}) do
      repo = Repo.current
      assert_equal({Repo::REPO => repo}, Repo.env)
    end
  end
  
  #
  # initialize test
  #
  
  def test_repo_initializes_to_pwd_by_default
    repo = Repo.new
    assert_equal Dir.pwd, repo.path
  end
  
  #
  # git test
  #
  
  def test_git_auto_initializes_using_path
    assert_equal nil, repo.env[Repo::GIT]
    git = repo.git
    assert_equal git, repo.env[Repo::GIT]
    assert_equal File.join(repo.path, '.git'), git.path
  end
  
  #
  # idx test
  #
  
  def test_idx_auto_initializes_using_git_path_and_branch
    assert_equal nil, repo.env[Repo::IDX]
    idx = repo.idx
    assert_equal idx, repo.env[Repo::IDX]
    assert_equal File.join(git.work_dir, 'index', git.branch), idx.path
  end
  
  #
  # cache test
  #

  def test_cache_returns_CACHE_set_in_env
    repo.env[Repo::CACHE] = :cache
    assert_equal :cache, repo.cache
  end

  def test_cache_auto_initializes_to_hash
    assert_equal false, repo.env.has_key?(Repo::CACHE)
    assert_equal Hash, repo.cache.class
    assert_equal true, repo.env.has_key?(Repo::CACHE)
  end

  def test_cache_reads_and_caches_attrs
    a = repo.store('content' => 'a')
    b = repo.cache[a]

    assert_equal 'a', b['content']
    assert_equal b.object_id, repo.cache[a].object_id
  end
  
  #
  # store test
  #
  
  def test_store_serializes_and_stores_attributes
    sha = repo.store('key' => 'value')
    assert_equal serialize('key' => 'value'), git.get(:blob, sha).data
  end
  
  def test_store_stores_attributes_at_current_time_in_utc
    sha = repo.store
    date = Time.now.utc
    assert_equal git.get(:blob, sha).data, git[date.strftime("%Y/%m%d/#{sha}")]
  end
  
  def test_store_caches_attrs
    attrs = {'content' => 'a'}
    a = repo.store(attrs)
    
    assert_equal({a => attrs}, repo.cache)
  end
  
  #
  # read test
  #
  
  def test_read_returns_a_deserialized_hash_for_sha
    sha = git.set(:blob, serialize('key' => 'value'))
    attrs = repo.read(sha)
    
    assert_equal 'value', attrs['key']
  end
  
  def test_read_returns_nil_for_non_documents
    sha = git.set(:blob, "content")
    assert_equal nil, repo.read(sha)
  end
  
  #
  # link test
  #

  def test_link_links_parent_to_child_using_an_empty_sha
    a, b = create_nodes('a', 'b')
    repo.link(a, b)
    
    assert_equal '', git[Repo::Utils.sha_path(a, b)]
  end
  
  def test_link_raises_an_error_when_linking_to_self
    a = repo.store
    err = assert_raises(RuntimeError) { repo.link(a, a) }
    assert_equal "cannot link to self: #{a} -> #{a}", err.message
  end
  
  def test_update_raises_an_error_when_linking_to_update
    a, b = create_nodes('a', 'b')
    repo.update(a, b)
    
    err = assert_raises(RuntimeError) { repo.link(a, b) }
    assert_equal "cannot link to an update: #{a} -> #{b}", err.message
  end
  
  #
  # update test
  #
  
  def test_update_links_original_to_update_using_original_sha
    a, b = create_nodes('a', 'b')
    repo.update(a, b)
    
    assert_equal git.get(:blob, a).data, git[Repo::Utils.sha_path(a, b)]
  end
  
  def test_update_creates_a_back_reference_to_original_sha
    a, b = create_nodes('a', 'b')
    repo.update(a, b)
    
    assert_equal git.get(:blob, a).data, git[Repo::Utils.sha_path(b, b)]
  end
  
  def test_update_raises_an_error_when_updating_to_self
    a = repo.store
    err = assert_raises(RuntimeError) { repo.update(a, a) }
    assert_equal "cannot update with self: #{a} -> #{a}", err.message
  end
  
  def test_update_raises_an_error_when_updating_with_a_child
    a, b = create_nodes('a', 'b')
    repo.link(a, b)
    
    err = assert_raises(RuntimeError) { repo.update(a, b) }
    assert_equal "cannot update with a child: #{a} -> #{b}", err.message
  end
  
  def test_update_raises_an_error_when_updating_with_an_existing_update
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    
    err = assert_raises(RuntimeError) { repo.update(c, b) }
    assert_equal "cannot update with an update: #{c} -> #{b}", err.message
  end
  
  #
  # linkage test
  #
  
  def test_linkage_returns_the_sha_for_the_linkage
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    
    empty_sha = git.set(:blob, '')
    assert_equal empty_sha, repo.linkage(a, b)
    assert_equal b, repo.linkage(b, c)
    assert_equal b, repo.linkage(c, c)
  end
  
  def test_linkage_returns_nil_if_no_such_link_exists
    a, b = create_nodes('a', 'b')
    
    assert_equal nil, repo.linkage(a, a)
    assert_equal nil, repo.linkage(a, b)
  end
  
  #
  # linked? test
  #
  
  def test_linked_check_returns_true_if_the_shas_are_linked_as_parent_child
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    
    assert_equal false, repo.linked?(a, a)
    assert_equal true, repo.linked?(a, b)
    assert_equal false, repo.linked?(b, c)
  end
  
  #
  # original? test
  #
  
  def test_original_check_returns_true_if_sha_is_the_head_of_an_update_chain
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.update(b, c)
    
    assert_equal true, repo.original?(a)
    assert_equal false, repo.original?(b)
    assert_equal false, repo.original?(c)
  end
  
  #
  # update? test
  #
  
  def test_update_check_returns_true_if_sha_is_an_update
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.update(b, c)
    
    assert_equal false, repo.update?(a)
    assert_equal true, repo.update?(b)
    assert_equal true, repo.update?(c)
  end
  
  #
  # updated? test
  #
  
  def test_updated_check_returns_true_if_sha_has_been_udpated
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.update(b, c)
    
    assert_equal true, repo.updated?(a)
    assert_equal true, repo.updated?(b)
    assert_equal false, repo.updated?(c)
  end
  
  #
  # current? test
  #
  
  def test_current_check_returns_true_if_sha_is_a_tail_of_an_update_chain
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.update(b, c)
    
    assert_equal false, repo.current?(a)
    assert_equal false, repo.current?(b)
    assert_equal true, repo.current?(c)
  end
  
  #
  # tail? test
  #
  
  def test_tail_check_returns_true_if_sha_has_no_links
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)
    
    assert_equal false, repo.tail?(a)
    assert_equal false, repo.tail?(b)
    assert_equal true, repo.tail?(c)
  end
  
  #
  # original test
  #
  
  def test_original_returns_sha_if_sha_has_not_been_updated
    a = repo.store
    assert_equal a, repo.original(a)
  end
  
  def test_original_returns_sha_for_the_head_of_an_update_chain
    a, b, c = create_nodes('a', 'b', 'c')
    repo.update(a, b)
    repo.update(b, c)
    
    assert_equal a, repo.original(b)
    assert_equal a, repo.original(c)
  end
  
  #
  # previous test
  #
  
  def test_previous_returns_backreference_to_updated_sha
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    assert_equal nil, repo.previous(a)
    assert_equal a, repo.previous(b)
    assert_equal a, repo.previous(c)
    assert_equal c, repo.previous(d)
  end
  
  #
  # updates test
  #

  def test_updates_returns_array_of_updates_to_sha
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    assert_equal [b, c].sort, repo.updates(a).sort
    assert_equal [], repo.updates(b)
    assert_equal [d], repo.updates(c)
    assert_equal [], repo.updates(d)
  end
  
  #
  # current test
  #

  def test_current_returns_array_of_current_revisions
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.update(a, b)
    repo.update(a, c)
    repo.update(c, d)
    
    assert_equal [b, d].sort, repo.current(a).sort
    assert_equal [b], repo.current(b)
    assert_equal [d], repo.current(c)
    assert_equal [d], repo.current(d)
  end

  #
  # links test
  #

  def test_links_returns_array_of_linked_shas
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.link(a, c)

    assert_equal [b, c].sort, repo.links(a).sort
    assert_equal [], repo.links(b)
  end
  
  def test_links_does_not_return_updates
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(a, c)
    
    assert_equal [b], repo.links(a)
  end
  
  def test_links_concats_links_of_previous_for_update
    a, b, c, x, y, z = create_nodes('a', 'b', 'c', 'x', 'y', 'z')
    repo.update(a, b)
    repo.update(b, c)
    repo.link(a, x)
    repo.link(b, y)
    repo.link(c, z)
    
    assert_equal [x], repo.links(a)
    assert_equal [x, y].sort, repo.links(b).sort
    assert_equal [x, y, z].sort, repo.links(c).sort
  end
  
  #
  # each_linkage test
  #
  
  def test_each_linkage_yields_each_forward_linkage_with_flag_for_update
    a, b, c, d = create_nodes('a', 'b', 'c', 'd')
    repo.link(a, b)
    repo.link(a, c)
    repo.update(a, d)
    
    updates = []
    links = []
    repo.each_linkage(a) do |sha, update|
      (update ? updates : links) << sha
    end
    
    assert_equal [b, c].sort, links.sort
    assert_equal [d], updates.sort
  end

  #
  # each test
  #
  
  def test_each_yields_each_doc_to_the_block_reverse_ordered_by_date
    a = repo.store({'content' => 'a'}, Time.utc(2009, 9, 11))
    b = repo.store({'content' => 'b'}, Time.utc(2009, 9, 10))
    c = repo.store({'content' => 'c'}, Time.utc(2009, 9, 9))
    
    results = []
    repo.each {|sha| results << sha }
    assert_equal [a, b, c], results
  end
  
  def test_each_does_not_yield_non_doc_entries_in_repo
    a = repo.store({'content' => 'a'}, Time.utc(2009, 9, 11))
    b = repo.store({'content' => 'b'}, Time.utc(2009, 9, 10))
    c = repo.store({'content' => 'c'}, Time.utc(2009, 9, 9))
    
    git.add(
      "year/mmdd" => "skipped",
      "00/0000" => "skipped",
      "0000/00" => "skipped"
    )
    
    results = []
    repo.each {|sha| results << sha }
    assert_equal [a, b, c], results
  end
  
  #
  # timeline test
  #
  
  def test_timeline_returns_the_most_recently_added_docs
    a = repo.store({'content' => 'a'}, Time.utc(2009, 9, 11))
    d = repo.store({'content' => 'd'}, Time.utc(2009, 9, 10))
    c = repo.store({'content' => 'c'}, Time.utc(2009, 9, 9))
    
    b = repo.store({'content' => 'b'}, Time.utc(2008, 9, 10))
    e = repo.store({'content' => 'e'}, Time.utc(2008, 9, 9))
    
    assert_equal [a, d, c, b, e], repo.timeline
    assert_equal [ d, c, b], repo.timeline(:n => 3, :offset => 1)
  end

  #
  # diff test
  #
  
  def test_diff_returns_shas_added_from_a_to_b
    one = repo.store('content' => 'one')
    a = git.commit!('added one')
    
    two = repo.store('content' => 'two')
    b = git.commit!('added two')
    
    three = repo.store('content' => 'three')
    c = git.commit!('added three')
    
    assert_equal [two, three].sort, repo.diff(a, c).sort
    assert_equal [], repo.diff(c, a)
    
    assert_equal [three].sort, repo.diff(b, c)
    assert_equal [], repo.diff(c, b)
    
    assert_equal [], repo.diff(a, a)
    assert_equal [], repo.diff(c, c)
  end
  
  def test_diff_treats_nil_as_prior_to_initial_commit
    one = repo.store('content' => 'one')
    a = git.commit!('added one')
    
    assert_equal [one], repo.diff(nil, a)
    assert_equal [], repo.diff(a, nil)
  end
  
  #
  # status test
  #
  
  def test_status_returns_formatted_lines_of_status
    assert_equal '', repo.status
    
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    
    assert_equal [
      "+ doc    #{a}",
      "+ doc    #{b}",
      "+ doc    #{c}",
      "+ link   #{a} to  #{b}",
      "+ update #{c} was #{b}"
    ].sort, repo.status.split("\n")
  end
  
  def test_status_converts_shas_as_determined_by_block
    a, b, c = create_nodes('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    
    actual = repo.status {|sha| sha[0,8] }
    assert_equal [
      "+ doc    #{a[0,8]}",
      "+ doc    #{b[0,8]}",
      "+ doc    #{c[0,8]}",
      "+ link   #{a[0,8]} to  #{b[0,8]}",
      "+ update #{c[0,8]} was #{b[0,8]}"
    ].sort, actual.split("\n")
  end
  
  #
  # commit test
  #
  
  def test_commit_commits_with_status_by_default
    a, b = create_nodes('a', 'b')
    status = repo.status
    sha = repo.commit
    
    assert_equal status, git.get(:commit, sha).message
  end
end