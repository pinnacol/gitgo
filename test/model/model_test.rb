require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/git'

# These model tests are intended to test the various add/remove scenarios and
# to ensure that pull will cleanly rebase changes together.
#
# == Issue Scenarios
#
# add an issue:
# * adds    issues/_issue
# * adds    _issue/_index.i
#
# modify an issue:
# * adds    _parent_comment/_comment
# * removes _issue/_current.i
# * adds    _issue/_index.i
#
# remove an issue:
# * removes issues/_issue
# * removes _issue/* (recursive)
#
# rename/update an issue definition:
# * removes issues/_old_issue
# * adds    issues/_new_issue
# * renames _old_issue as _new_issue
# * updates index
#
# == Page Scenarios
#
# add a page:
# * adds    pages/page
#
# remove a page:
# * remove  pages/page
#
# update a page:
# * update  pages/page
#
class ModelTest < Test::Unit::TestCase
  include RepoTestHelper
  Git = Gitgo::Git
  
  attr_accessor :a_path, :b_path, :a, :b
  
  def setup
    super
    @a_path = method_root.path(:tmp, 'a')
    @b_path = method_root.path(:tmp, 'b')
    
    @a = Git.init(a_path)
    a.add("one" => "one content").commit("a added one")
    
    @b = a.clone(b_path)
  end
  
  # For some reason repo.repo.commits (used in the log assertions) does not
  # consistently order the output... perhaps because the commits in a test
  # will all have the same commit date.  Hence the log assertions simply
  # ensure the correct messages are somewhere in the log.
  def assert_log_equal(expected, repo)
    assert_equal expected.sort, repo.grit.commits('gitgo').collect {|c| c.message }.sort
  end
  
  # For reference, these were the objects after this method (only replicable
  # with my user.name and user.email of course course):
  #
  # e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 README
  # 543b9bebdc6bd5c4b22136034a95dd097a57d3dd initial tree
  # 84a423e858ccab4f948cfbe8207a6b1927916055 initial commit
  #    
  # 6b584e8ece562ebffc15d38808cd6b98fc3d97ea two
  #
  # "content"
  #
  # 76d2e8ed85944fb73165a30e6da0026c1dbd7579 two tree
  #    
  # "tree 68\000100644
  # README\000\346\235\342\233\262\321\326CK\213)\256wZ\330\302\344\214S\22110
  # 0644 two\000kXN\216\316V.\277\374\025\323\210\b\315k\230\374=\227\352"
  #    
  # f95d93552b334290b1e39f069bbbd0d6dce92bf5 two commit
  #    
  # "commit 236\000tree 76d2e8ed85944fb73165a30e6da0026c1dbd7579\nparent
  # 84a423e858ccab4f948cfbe8207a6b1927916055\nauthor Simon Chiang
  # <simon.chiang@pinnacol.com> 1255708078 -0600\ncommitter Simon Chiang
  # <simon.chiang@pinnacol.com> 1255708078 -0600\n\nmessage\n"
  #
  def test_manual_commit_and_merge
    sh(a_path, "git status")
    sh(a_path, "git checkout gitgo")
    
    method_root.prepare(:tmp, 'a/two') {|io| io << "two content" }
    
    sh(a_path, "git add .")
    sh(a_path, "git commit -m 'message'")

    a.reset
    b.reset
    assert_equal "two content", a['two']
    assert_equal nil, b['two']
    
    sh(b_path, "git checkout gitgo")
    sh(b_path, "git pull")
    
    a.reset
    b.reset
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
  end
  
  #
  # pull(merge) tests
  #
  
  # example: a adds an issue and b pulls
  def test_pull_a_new_file
    a.add("two" => "two content").commit("a added two")
    
    assert_equal "two content", a['two']
    assert_equal nil, b['two']
    
    b.pull
    
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
    
    assert_log_equal [
      "a added one",
      "a added two"
    ], b
  end
  
  # example: a modifies an issue, b modifies the same issue and pulls
  def test_pull_a_new_file_into_a_modified_tree
    b.add("dir/three" => "three content").commit("b added three")
    a.add("dir/two"   => "two content").commit("a added two")
    
    assert_equal "two content", a['dir/two']
    assert_equal nil, b['dir/two']
    assert_equal "three content", b['dir/three']
    
    b.pull
    
    assert_equal "two content", a['dir/two']
    assert_equal "two content", b['dir/two']
    assert_equal "three content", b['dir/three']
    
    assert_log_equal [
      "a added one",
      "a added two",
      "b added three", 
      "gitgo merge of origin/gitgo into gitgo"
    ], b
  end
  
  # example: unlikely scenario where both repos add the exact same file
  #
  # Note that in this case, due to rebasing, the b comment is lost.  Seems bad
  # but remember all true content MUST be kept in the files themselves; the
  # commit history should be entirely expendable and in fact should be
  # designed to have the same message in both cases anyhow.
  def test_add_the_same_file_in_both_repos
    a.add("two" => "two content").commit("a added two")
    b.add("two" => "two content").commit("b added two")
    
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
    
    b.pull
    
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
    
    assert_log_equal [
      "a added one",
      "a added two", 
      "b added two",
      "gitgo merge of origin/gitgo into gitgo"
    ], b
  end
  
  # example: a updates a comment, removing the old comment
  def test_remove_a_file
    a.rm("one").commit("a removed one")
    
    assert_equal nil, a['one']
    assert_equal "one content", b['one']
    
    b.pull
    
    assert_equal nil, a['one']
    assert_equal nil, b['one']
    
    assert_log_equal [
      "a added one",
      "a removed one"
    ], b
  end
  
  # example: a updates an issue, b updates an issue, and as a result the index
  # file for the issue is removed in both.  note the commit log loss as above
  def test_remove_the_same_file_in_both_repos
    a.rm("one").commit("a removed one")
    b.rm("one").commit("b removed one")
    
    assert_equal nil, a['one']
    assert_equal nil, b['one']
    
    b.pull
    
    assert_equal nil, a['one']
    assert_equal nil, b['one']
    
    assert_log_equal [
      "a added one",
      "a removed one",
      "b removed one",
      "gitgo merge of origin/gitgo into gitgo"
    ], b
  end
  
  # Unlikely/impossible scenario, but for completeness...
  def test_add_back_a_remotely_removed_file
    a.add("two" => "two content").commit("a added two")
    a.rm("two").commit("a removed two")
    b.add("two" => "two content").commit("b added two")
    
    assert_equal nil, a['two']
    assert_equal "two content", b['two']
    
    b.pull
    
    assert_equal nil, a['two']
    assert_equal "two content", b['two']
    
    assert_log_equal [
      "a added one",
      "a added two",
      "a removed two",
      "b added two", 
      "gitgo merge of origin/gitgo into gitgo"
    ], b
  end
end