require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class ModelTest < Test::Unit::TestCase
  include RepoTestHelper
  Repo = Gitgo::Repo
  
  attr_accessor :a_path, :b_path, :a, :b
  
  def setup
    super
    @a_path = method_root.path(:tmp, 'a')
    @b_path = method_root.path(:tmp, 'b')
    
    @a = Repo.init(a_path)
    a.add("one" => "one content").commit("a added one")
    
    @b = a.clone(b_path)
  end
  
  def assert_log_equal(expected, repo)
    assert_equal expected, repo.repo.commits('gitgo').sort_by {|c| c.committed_date }.collect {|c| c.message }
  end
  
  # Executes the command, capturing output to a tmp file.  Returns the command
  # output.
  def sh(cmd)
    puts cmd if ENV['VERBOSE'] == 'true'
    path = method_root.prepare(:tmp, 'stdout')
    system("#{cmd} > '#{path}' 2>&1")
    File.exists?(path) ? File.read(path) : nil
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
    Dir.chdir(a_path) do 
      sh "git checkout gitgo"
      method_root.prepare(:tmp, 'a/two') {|io| io << "two content" }
      
      sh "git add ."
      sh "git commit -m 'message'"
    end
    
    assert_equal "two content", a['two']
    assert_equal nil, b['two']
    
    Dir.chdir(b_path) do
      sh "git checkout gitgo"
      sh "git pull"
    end
    
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
  end
  
  #
  # pull tests
  #
  
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
  
  def test_add_a_file_in_both_repos
    a.add("two" => "two content").commit("a added two")
    b.add("two" => "two content").commit("b added two")
    
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
    
    b.pull
    
    assert_equal "two content", a['two']
    assert_equal "two content", b['two']
    
    assert_log_equal [
      "a added two",
      "a added one",
      "b added two",
      "Merge branch 'gitgo' of #{File.dirname(a.path)}/ into gitgo"
    ], b
  end
  
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
  
  def test_remove_a_file_in_both_repos
    a.rm("one").commit("a removed one")
    b.rm("one").commit("b removed one")
    
    assert_equal nil, a['one']
    assert_equal nil, b['one']
    
    b.pull
    
    assert_equal nil, a['one']
    assert_equal nil, b['one']
  end
  
  def test_merge_removed_file
    a.add("two" => "two content").commit("a added two")
    a.rm("two").commit("a removed two")
    b.add("two" => "two content").commit("b added two")
    
    assert_equal nil, a['two']
    assert_equal "two content", b['two']
    
    b.pull
    
    assert_equal nil, a['two']
    assert_equal "two content", b['two']
    
    assert_log_equal [
      "a added two",
      "a removed two",
      "a added one",
      "b added two",
      "Merge branch 'gitgo' of #{File.dirname(a.path)}/ into gitgo"
    ], b
  end
end