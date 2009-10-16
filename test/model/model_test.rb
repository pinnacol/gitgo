require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/repo'

class ModelTest < Test::Unit::TestCase
  include RepoTestHelper
  Repo = Gitgo::Repo
  
  attr_accessor :a_path, :b_path, :a, :b
  
  def setup
    super
    repo_path = File.expand_path('bare.git', FIXTURE_DIR)
    @a_path = method_root.path(:tmp, 'a')
    @b_path = method_root.path(:tmp, 'b')
    
    sh "git clone '#{repo_path}' '#{a_path}'"
    sh "GIT_DIR='#{a_path}/.git' git branch gitgo --track origin/gitgo"
    sh "git clone '#{a_path}' '#{b_path}'"
    sh "GIT_DIR='#{b_path}/.git' git branch gitgo --track origin/gitgo"
    
    @a = Repo.init(a_path)
    @b = Repo.init(b_path)
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
  # 6b584e8ece562ebffc15d38808cd6b98fc3d97ea sample
  #
  # "content"
  #
  # 76d2e8ed85944fb73165a30e6da0026c1dbd7579 sample tree
  #    
  # "tree 68\000100644
  # README\000\346\235\342\233\262\321\326CK\213)\256wZ\330\302\344\214S\22110
  # 0644 sample\000kXN\216\316V.\277\374\025\323\210\b\315k\230\374=\227\352"
  #    
  # f95d93552b334290b1e39f069bbbd0d6dce92bf5 sample commit
  #    
  # "commit 236\000tree 76d2e8ed85944fb73165a30e6da0026c1dbd7579\nparent
  # 84a423e858ccab4f948cfbe8207a6b1927916055\nauthor Simon Chiang
  # <simon.chiang@pinnacol.com> 1255708078 -0600\ncommitter Simon Chiang
  # <simon.chiang@pinnacol.com> 1255708078 -0600\n\nmessage\n"
  #
  def test_manual_commit_and_merge
    Dir.chdir(a_path) do 
      sh "git checkout gitgo"
      method_root.prepare(:tmp, 'a/sample') {|io| io << "content" }
      
      sh "git add ."
      sh "git commit -m 'message'"
    end
    
    assert_equal "content", a['sample']
    assert_equal nil, b['sample']
    
    Dir.chdir(b_path) do
      sh "git checkout gitgo"
      sh "git pull"
    end
    
    assert_equal "content", a['sample']
    assert_equal "content", b['sample']
  end
  
  def test_repo_commit_and_merge
    a['sample'] = "content"
    a.commit "message"
    
    assert_equal "content", a['sample']
    assert_equal nil, b['sample']
    
    Dir.chdir(b_path) do
      sh "git checkout gitgo"
      sh "git pull"
    end
    
    assert_equal "content", a['sample']
    assert_equal "content", b['sample']
  end

end