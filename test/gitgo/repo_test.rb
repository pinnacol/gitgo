require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class RepoTest < Test::Unit::TestCase
  acts_as_file_test
  
  Git = Gitgo::Git
  Index = Gitgo::Index
  Repo = Gitgo::Repo
  
  attr_accessor :git, :idx, :repo
  
  def setup
    super
    @git = Git.init method_root.path(:repo)
    @idx = Index.new method_root.path(:index)
    @repo = Repo.new(Repo::GIT => git, Repo::IDX => idx)
  end
  
  def serialize(attrs)
    JSON.generate(attrs)
  end
  
  def create_docs(*contents)
    date = Time.now
    contents.collect do |content|
      date += 1
      repo.store("content" => content, "date" => date)
    end
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
    a, b = create_docs('a', 'b')
    repo.link(a, b)
    
    assert_equal '', git[Repo::Utils.sha_path(a, b)]
  end
  
  def test_link_raises_an_error_when_linking_to_self
    a = repo.store
    err = assert_raises(RuntimeError) { repo.link(a, a) }
    assert_equal "cannot link to self: #{a} -> #{a}", err.message
  end
  
  def test_update_raises_an_error_when_linking_to_update
    a, b = create_docs('a', 'b')
    repo.update(a, b)
    
    err = assert_raises(RuntimeError) { repo.link(a, b) }
    assert_equal "cannot link to an update: #{a} -> #{b}", err.message
  end
  
  #
  # update test
  #
  
  def test_update_links_original_to_update_using_original_sha
    a, b = create_docs('a', 'b')
    repo.update(a, b)
    
    assert_equal git.get(:blob, a).data, git[Repo::Utils.sha_path(a, b)]
  end
  
  def test_update_creates_a_back_reference_to_original_sha
    a, b = create_docs('a', 'b')
    repo.update(a, b)
    
    assert_equal git.get(:blob, a).data, git[Repo::Utils.sha_path(b, b)]
  end
  
  def test_update_raises_an_error_when_updating_to_self
    a = repo.store
    err = assert_raises(RuntimeError) { repo.update(a, a) }
    assert_equal "cannot update with self: #{a} -> #{a}", err.message
  end
  
  def test_update_raises_an_error_when_updating_with_a_child
    a, b = create_docs('a', 'b')
    repo.link(a, b)
    
    err = assert_raises(RuntimeError) { repo.update(a, b) }
    assert_equal "cannot update with a child: #{a} -> #{b}", err.message
  end
  
  def test_update_raises_an_error_when_updating_with_an_existing_update
    a, b, c = create_docs('a', 'b', 'c')
    repo.update(a, b)
    
    err = assert_raises(RuntimeError) { repo.update(c, b) }
    assert_equal "cannot update with an update: #{c} -> #{b}", err.message
  end
  
  #
  # linkage test
  #
  
  def test_linkage_returns_the_sha_for_the_linkage
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    
    empty_sha = git.set(:blob, '')
    assert_equal empty_sha, repo.linkage(a, b)
    assert_equal b, repo.linkage(b, c)
    assert_equal b, repo.linkage(c, c)
  end
  
  def test_linkage_returns_nil_if_no_such_link_exists
    a, b = create_docs('a', 'b')
    
    assert_equal nil, repo.linkage(a, a)
    assert_equal nil, repo.linkage(a, b)
  end
  
  #
  # linked? test
  #
  
  def test_linked_check_returns_true_if_the_shas_are_linked_as_parent_child
    a, b, c = create_docs('a', 'b', 'c')
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
    a, b, c = create_docs('a', 'b', 'c')
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
    a, b, c = create_docs('a', 'b', 'c')
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
    a, b, c = create_docs('a', 'b', 'c')
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
    a, b, c = create_docs('a', 'b', 'c')
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
    a, b, c = create_docs('a', 'b', 'c')
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
    a, b, c = create_docs('a', 'b', 'c')
    repo.update(a, b)
    repo.update(b, c)
    
    assert_equal a, repo.original(b)
    assert_equal a, repo.original(c)
  end
  
  #
  # previous test
  #
  
  def test_previous_returns_backreference_to_updated_sha
    a, b, c, d = create_docs('a', 'b', 'c', 'd')
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
    a, b, c, d = create_docs('a', 'b', 'c', 'd')
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
    a, b, c, d = create_docs('a', 'b', 'c', 'd')
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
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.link(a, c)

    assert_equal [b, c].sort, repo.links(a).sort
    assert_equal [], repo.links(b)
  end
  
  def test_links_does_not_return_updates
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.update(a, c)
    
    assert_equal [b], repo.links(a)
  end
  
  def test_links_concats_links_of_previous_for_update
    a, b, c, x, y, z = create_docs('a', 'b', 'c', 'x', 'y', 'z')
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
  # each_link test
  #
  
  def test_each_link_yields_each_forward_linkage_with_flag_for_update
    a, b, c, d = create_docs('a', 'b', 'c', 'd')
    repo.link(a, b)
    repo.link(a, c)
    repo.update(a, d)
    
    updates = []
    links = []
    repo.each_link(a) do |sha, update|
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
  # diff test
  #
  
  def test_diff_returns_shas_added_from_a_to_b
    one = repo.store("content" => "one")
    a = git.commit!("added one")
    
    two = repo.store("content" => "two")
    b = git.commit!("added two")
    
    three = repo.store("content" => "three")
    c = git.commit!("added three")
    
    assert_equal [two, three].sort, repo.diff(c, a).sort
    assert_equal [], repo.diff(a, c)
    
    assert_equal [three].sort, repo.diff(c, b)
    assert_equal [], repo.diff(b, c)
    
    assert_equal [], repo.diff(a, a)
    assert_equal [], repo.diff(c, c)
  end
  
  def test_diff_treats_nil_as_prior_to_initial_commit
    one = repo.store("content" => "one")
    a = git.commit!("added one")
    
    assert_equal [one], repo.diff(nil, a)
    assert_equal [], repo.diff(a, nil)
  end
end