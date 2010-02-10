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
      repo.create("content" => content, "date" => date)
    end
  end
  
  #
  # create test
  #
  
  def test_create_stores_attributes_and_returns_the_blob_sha
    sha = repo.create('key' => 'value')
    assert_equal serialize('key' => 'value'), git.get(:blob, sha).data
  end
  
  def test_create_stores_document_at_current_time_in_utc
    sha = repo.create
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

  def test_link_links_parent_to_child
    a, b = create_docs('a', 'b')
    repo.link(a, b)
    assert_equal [b], repo.children(a)
    assert_equal [a], repo.parents(b)
  end
  
  #
  # update test
  #

  def test_update_links_old_doc_to_new_doc_as_an_update
    a, b = create_docs('a', 'b')
    repo.update(a, b)
    assert_equal [b], repo.updates(a)
  end

  #
  # parents test
  #

  def test_parents_returns_array_of_parents_linking_to_child
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, c)
    repo.link(b, c)
    
    assert_equal [a, b].sort, repo.parents(c).sort
    assert_equal [], repo.parents(b)
  end

  #
  # children test
  #

  def test_children_returns_array_of_linked_children
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.link(a, c)

    assert_equal [b, c].sort, repo.children(a).sort
    assert_equal [], repo.children(b)
  end
  
  def test_children_does_not_return_updates
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.update(a, c)
    
    assert_equal [b], repo.children(a)
  end
  
  #
  # tree test
  #
  
  def test_tree_returns_an_tree_of_shas
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)
    
    expected = {
      nil => [a],
      a => [b], 
      b => [c], 
      c => []
    }
    
    assert_equal expected, repo.tree(a)
  end

  def test_tree_allows_merge_linkages
    a, b, c, d = create_docs('a', 'b', 'c', 'd')
    repo.link(a, b).link(b, d)
    repo.link(a, c).link(c, d)
    
    expected = {
      nil => [a],
      a => [b, c].sort,
      b => [d],
      c => [d],
      d => []
    }
    
    assert_equal expected, repo.tree(a)
  end
  
  def test_tree_sorts_by_block
    a, b, c, d = create_docs('a', 'b', 'c', 'd')
    repo.link(a, b)
    repo.link(a, c)
    repo.link(a, d)
    
    expected = {
      nil => [a],
      a => [b, c, d].sort.reverse,
      b => [],
      c => [],
      d => []
    }
    actual = repo.tree(a) {|a, b| b <=> a }
    
    assert_equal expected, actual
  end
  
  def test_tree_deconvolutes_updates
    a, b, c, d, m, n, x, y = create_docs('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, d)
    repo.update(a, x).link(x, y)
    repo.update(b, m).link(m, n)
    
    expected = {
      nil => [x],
      a => nil,
      b => nil,
      c => [d],
      d => [],
      x => [y, m].sort,
      y => [],
      m => [n, c].sort,
      n => []
    }
    
    assert_equal expected, repo.tree(a)
  end
  
  def test_tree_detects_circular_linkage
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, a)
    
    err = assert_raises(RuntimeError) { repo.tree(a) }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{c}
  #{a}
}, err.message
  end

  def test_tree_detects_circular_linkage_with_replacement
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    repo.link(b, a)
    
    err = assert_raises(RuntimeError) { repo.tree(a) }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{a}
}, err.message
  end
  
  def test_tree_detects_circular_linkage_through_replacement
    a, b, c = create_docs('a', 'b', 'c')
    repo.link(a, b)
    repo.update(b, c)
    repo.link(c, a)

    err = assert_raises(RuntimeError) { repo.tree(a) }
    assert_equal %Q{circular link detected:
  #{a}
  #{b}
  #{c}
  #{a}
}, err.message
  end
  
  #
  # list_tree test
  #
  
  def date_sort
    lambda {|a, b| repo.read(a)['date'] <=> repo.read(b)['date'] }
  end
  
  def test_list_tree_documentation
    a, b, c, d, e = create_docs('a', 'b', 'c', 'd', 'e')
    repo.link(a, b)
    repo.link(b, c).link(b, d)
    repo.link(d, e)
    
    expected = [a, b, [c], [d, e]]
    actual = repo.list_tree(a, &date_sort)
    
    assert_equal expected, actual
  end
  
  def test_list_tree_deconvolutes_updates
    a, b, c, d, m, n, x, y = create_docs('a', 'b', 'c', 'd', 'm', 'n', 'x', 'y')
    repo.link(a, b)
    repo.link(b, c)
    repo.link(c, d)
    repo.update(a, x).link(x, y)
    repo.update(b, m).link(m, n)
    
    tree = repo.list_tree(a, &date_sort)
    assert_equal [x, [m, [c, d], [n]], [y]], tree
  end
  
  def test_list_tree_with_multiple_heads
    a, b, m, n, x, y = create_docs('a', 'b', 'm', 'n', 'x', 'y')
    repo.link(a, b).update(a, m).update(a, x)
    repo.link(m, n)
    repo.link(x, y)
    
    tree = repo.list_tree(a, &date_sort)
    assert_equal [[m, [b], [n]], [x, [b], [y]]], tree
  end

  #
  # each test
  #
  
  def test_each_yields_each_doc_to_the_block_reverse_ordered_by_date
    a = repo.create({'content' => 'a'}, Time.utc(2009, 9, 11))
    b = repo.create({'content' => 'b'}, Time.utc(2009, 9, 10))
    c = repo.create({'content' => 'c'}, Time.utc(2009, 9, 9))
    
    results = []
    repo.each {|sha| results << sha }
    assert_equal [a, b, c], results
  end
  
  def test_each_does_not_yield_non_doc_entries_in_repo
    a = repo.create({'content' => 'a'}, Time.utc(2009, 9, 11))
    b = repo.create({'content' => 'b'}, Time.utc(2009, 9, 10))
    c = repo.create({'content' => 'c'}, Time.utc(2009, 9, 9))
    
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
    one = repo.create("content" => "one")
    a = git.commit!("added one")
    
    two = repo.create("content" => "two")
    b = git.commit!("added two")
    
    three = repo.create("content" => "three")
    c = git.commit!("added three")
    
    assert_equal [two, three].sort, repo.diff(c, a).sort
    assert_equal [], repo.diff(a, c)
    
    assert_equal [three].sort, repo.diff(c, b)
    assert_equal [], repo.diff(b, c)
    
    assert_equal [], repo.diff(a, a)
    assert_equal [], repo.diff(c, c)
  end
  
  def test_diff_treats_nil_as_prior_to_initial_commit
    one = repo.create("content" => "one")
    a = git.commit!("added one")
    
    assert_equal [one], repo.diff(nil, a)
    assert_equal [], repo.diff(a, nil)
  end
end