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
  
  def index
    repo.index
  end
  
  def serialize(attrs)
    JSON.generate(attrs)
  end
  
  def shas(*contents)
    contents.collect do |content|
      repo.save("content" => content)
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
  # index test
  #
  
  def test_index_auto_initializes_using_git_path_and_branch
    assert_equal nil, repo.env[Repo::INDEX]
    index = repo.index
    assert_equal index, repo.env[Repo::INDEX]
    assert_equal File.join(git.work_dir, 'refs', git.branch, 'index'), index.path
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
    a = repo.save('content' => 'a')
    b = repo.cache[a]

    assert_equal 'a', b['content']
    assert_equal b.object_id, repo.cache[a].object_id
  end
  
  #
  # empty_sha
  #
  
  def test_empty_sha_returns_the_sha_for_an_empty_file
    assert_equal '', git.get(:blob, repo.empty_sha).data
  end
  
  #
  # branch? test
  #
  
  def test_branch_returns_true_if_commit_has_an_empty_gitgo_file_in_it
    assert_equal false, repo.branch?(git.head)
    
    git['gitgo'] = ''
    git.commit!("setup")
    
    assert_equal true, repo.branch?(git.head)
    
    git['a'] = 'content'
    git.commit!("added a")
    
    assert_equal true, repo.branch?(git.head)
    assert_equal true, repo.branch?(git.branch)
    
    git.checkout('fail_one')
    git['gitgo'] = 'not empty'
    git.commit!("setup")
    
    assert_equal false, repo.branch?(git.head)
    
    git.checkout('fail_two')
    git['not_gitgo'] = ''
    git.commit!("setup")
    
    assert_equal false, repo.branch?(git.head)
    assert_equal false, repo.branch?(git.branch)
  end
  
  #
  # save test
  #
  
  def test_save_serializes_and_saves_attributes
    sha = repo.save('key' => 'value')
    assert_equal serialize('key' => 'value'), git.get(:blob, sha).data
  end
  
  def test_save_caches_attrs
    attrs = {'content' => 'a'}
    a = repo.save(attrs)
    
    assert_equal({a => attrs}, repo.cache)
  end
  
  #
  # create test
  #
  
  def test_create_associates_sha_to_empty_sha
    a = shas('a').first
    repo.create(a)
    
    assert_equal [Repo::DEFAULT_MODE, a], git[repo.sha_path(a, repo.empty_sha), true]
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

  def test_link_associates_parent_to_child_using_default_mode_and_child_sha
    a, b = shas('a', 'b')
    repo.link(a, b)
    
    assert_equal [Repo::DEFAULT_MODE, b], git[repo.sha_path(a, b), true]
  end
  
  #
  # update test
  #
  
  def test_update_associates_old_sha_to_new_sha_update_mode_and_child_sha
    a, b = shas('a', 'b')
    repo.update(a, b)
    
    assert_equal [Repo::UPDATE_MODE, b], git[repo.sha_path(a, b), true]
  end
  
  #
  # delete test
  #
  
  def test_delete_links_sha_to_sha_with_empty_sha
    a = shas('a').first
    repo.delete(a)
    
    assert_equal [Repo::DEFAULT_MODE, repo.empty_sha], git[repo.sha_path(a, a), true]
  end
  
  #
  # assoc_sha test
  #
  
  def test_assoc_sha_returns_the_sha_for_the_document
    a, b, c = shas('a', 'b', 'c')
    repo.create(a)
    repo.link(a, b)
    repo.update(b, c)
    repo.delete(c)
    
    assert_equal a, repo.assoc_sha(a, repo.empty_sha)
    assert_equal b, repo.assoc_sha(a, b)
    assert_equal c, repo.assoc_sha(b, c)
    assert_equal c, repo.assoc_sha(c, c)
  end
  
  #
  # assoc_mode test
  #
  
  def test_assoc_mode_returns_the_mode_for_the_document
    a, b, c = shas('a', 'b', 'c')
    repo.create(a)
    repo.link(a, b)
    repo.update(b, c)
    repo.delete(c)
    
    assert_equal Repo::DEFAULT_MODE, repo.assoc_mode(a, repo.empty_sha)
    assert_equal Repo::DEFAULT_MODE, repo.assoc_mode(a, b)
    assert_equal Repo::UPDATE_MODE, repo.assoc_mode(b, c)
    assert_equal Repo::DEFAULT_MODE, repo.assoc_mode(c, c)
  end
  
  #
  # assoc_type test
  #
  
  def test_assoc_type_returns_the_assoc_type_given_the_source_target_and_mode
    a, b, c = shas('a', 'b', 'c')
    repo.create(a)
    repo.link(a, b)
    repo.update(b, c)
    repo.delete(c)
    
    assert_equal :create, repo.assoc_type(a, repo.empty_sha)
    assert_equal :link, repo.assoc_type(a, b)
    assert_equal :update, repo.assoc_type(b, c)
    assert_equal :delete, repo.assoc_type(c, c)
    
    assert_equal :invalid, repo.assoc_type(a, a)
    assert_equal :invalid, repo.assoc_type(b, repo.empty_sha)
  end
  
  #
  # each_assoc test
  #
  
  def test_each_assoc_yields_the_sha_and_mode_of_each_assoc_to_the_block
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.create(a)
    repo.link(a, b)
    repo.link(a, c)
    repo.update(a, d)
    repo.delete(a)
    
    heads = []
    links = []
    updates = []
    deletes = []
    
    repo.each_assoc(a) do |sha, type|
      case type
      when :create then heads
      when :link   then links
      when :update then updates
      when :delete then deletes
      end << sha
    end
    
    assert_equal [a], heads
    assert_equal [b, c].sort, links.sort
    assert_equal [d], updates
    assert_equal [a], deletes
  end
  
  #
  # associations test
  #
  
  def test_associations_returns_a_hash_describing_associations_for_the_sha
    a, b, c, d = shas('a', 'b', 'c', 'd')
    repo.create(a)
    repo.link(a, b)
    repo.link(a, c)
    repo.update(a, d)
    repo.delete(a)
    
    assert_equal({
      :create => true,
      :links => [b, c].sort,
      :updates => [d],
      :delete => true
    }, repo.associations(a))
    
    assert_equal({}, repo.associations(b))
  end
  
  #
  # each test
  #
  
  def test_each_yields_each_doc_to_the_block
    a = repo.create repo.save('content' => 'a')
    b = repo.create repo.save('content' => 'b')
    c = repo.create repo.save('content' => 'c')
    
    results = []
    repo.each {|sha| results << sha }
    assert_equal [a, b, c].sort, results.sort
  end
  
  #
  # timeline test
  #
  
  def test_timeline_returns_the_most_recently_added_docs_by_date_index
    a, d, c, b, e = [
      {'content' => 'a', 'date' => '20090911'},
      {'content' => 'd', 'date' => '20090910'},
      {'content' => 'c', 'date' => '20090909'},
      {'content' => 'b', 'date' => '20080910'},
      {'content' => 'e', 'date' => '20080909'}
    ].collect do |attrs|
      sha = repo.save(attrs)
      index['date'][attrs['date']] << index.idx(sha)
      sha
    end
    
    assert_equal [a, d, c, b, e], repo.timeline
    assert_equal [d, c, b], repo.timeline(:n => 3, :offset => 1)
  end
  
  #
  # diff test
  #
  
  def test_diff_returns_shas_added_from_a_to_b
    one, two, three = shas('one', 'two', 'three')
    repo.create(one)
    a = git.commit!('added one')

    repo.create(two)
    b = git.commit!('added two')
    
    repo.create(three)
    c = git.commit!('added three')
    
    assert_equal [two, three].sort, repo.diff(a, c).sort
    assert_equal [], repo.diff(c, a)
    
    assert_equal [three].sort, repo.diff(b, c)
    assert_equal [], repo.diff(c, b)
    
    assert_equal [], repo.diff(a, a)
    assert_equal [], repo.diff(c, c)
  end
  
  def test_diff_treats_nil_as_prior_to_initial_commit
    one = repo.save('content' => 'one')
    repo.create(one)
    a = git.commit!('added one')
    
    assert_equal [one], repo.diff(nil, a)
    assert_equal [], repo.diff(a, nil)
  end
  
  #
  # status test
  #
  
  def test_status_returns_formatted_lines_of_status
    assert_equal '', repo.status
    
    a, b, c = shas('a', 'b', 'c')
    repo.create(a)
    repo.link(a, b)
    repo.update(b, c)
    
    assert_equal [
      "+ doc    #{a}",
      "+ link   #{a} to  #{b}",
      "+ update #{c} was #{b}"
    ].sort, repo.status.split("\n")
  end
  
  def test_status_converts_shas_as_determined_by_block
    a, b, c = shas('a', 'b', 'c')
    repo.create(a)
    repo.link(a, b)
    repo.update(b, c)
    
    actual = repo.status {|sha| sha[0,8] }
    assert_equal [
      "+ doc    #{a[0,8]}",
      "+ link   #{a[0,8]} to  #{b[0,8]}",
      "+ update #{c[0,8]} was #{b[0,8]}"
    ].sort, actual.split("\n")
  end
  
  #
  # commit test
  #
  
  def test_commit_commits_with_status_by_default
    a, b = shas('a', 'b')
    repo.create(a)
    repo.create(b)
    
    status = repo.status
    sha = repo.commit
    
    assert_equal status, git.get(:commit, sha).message
  end
  
  def test_commit_sets_up_repo_if_necessary
    a = git.set(:blob, 'content')
    repo.create(a)
    
    sha = repo.commit('created content')
    assert_equal true, repo.branch?(sha)
    
    commit = git.get(:commit, sha)
    assert_equal 'created content', commit.message
    
    parent = commit.parents[0]
    assert_equal 'setup gitgo', parent.message
  end
  
  #
  # setup test
  #
  
  def test_setup_sets_up_tracking_of_remote_upstream_branch
    repo.checkout('orig')
    repo.setup
    
    clone = git.clone(method_root.path('clone'))
    clone.checkout('new')
    
    assert_equal nil, clone.head
    assert_equal nil, clone.upstream_branch
    
    Repo.new(Repo::GIT => clone).setup('origin/orig')
    
    assert_equal repo.head, clone.head
    assert_equal 'origin/orig', clone.upstream_branch
  end
  
  def test_setup_advances_self_to_local_upstream_branch
    repo.checkout('orig')
    repo.setup
    orig_head = repo.head
    
    repo.checkout('new')
    
    assert_equal nil, repo.head
    assert_equal nil, repo.upstream_branch
    
    repo.setup('orig')
    
    assert_equal orig_head, repo.head
    assert_equal nil, repo.upstream_branch
  end
  
  def test_setup_adds_gitgo_file_for_nil_upstream_branch
    assert_equal nil, repo.head
    repo.setup(nil)
    
    blob = git.get(:commit, repo.head).tree/Repo::FILE
    assert_equal '', blob.data
  end
  
  def test_setup_adds_gitgo_file_for_empty_upstream_branch
    assert_equal nil, repo.head
    repo.setup('')
    
    blob = git.get(:commit, repo.head).tree/Repo::FILE
    assert_equal '', blob.data
  end
  
  def test_setup_raises_error_if_head_is_not_nil
    git['file'] = 'content'
    git.commit!('made a commit')
    
    err = assert_raises(RuntimeError) { repo.setup }
    assert_equal "already setup on: gitgo (#{git.head})", err.message
  end
  
  def test_setup_raises_error_if_upstream_branch_is_not_a_gitgo_branch
    git['file'] = 'content'
    git.commit!('made a commit')
    
    upstream_branch = git.branch
    assert_equal false, repo.branch?(upstream_branch)
    
    repo.checkout('new')
    
    err = assert_raises(RuntimeError) { repo.setup(upstream_branch) }
    assert_equal "not a gitgo branch: #{upstream_branch.inspect}", err.message
  end
end