require File.dirname(__FILE__) + "/../test_helper"

class ManualTest < Test::Unit::TestCase
  include RepoTestHelper
  
  attr_reader :a, :b, :c
  
  def setup
    super
    
    simple = File.expand_path('simple.git', FIXTURE_DIR)
    @a = method_root.path(:tmp, 'a')
    @b = method_root.path(:tmp, 'b')
    @c = method_root.path(:tmp, 'c')
    
    `git clone '#{simple}' '#{a}'`
    `git clone '#{a}' '#{b}'`
    `git clone '#{a}' '#{c}'`
    
    puts "\n#{method_name}" if ENV['DEBUG'] == 'true'
  end
  
  #
  # manual tests
  #
  
  def test_status
    output = "# On branch master\nnothing to commit (working directory clean)"
    assert_equal output, sh(a, 'git status')
    assert_equal output, sh(b, 'git status')
    assert_equal output, sh(c, 'git status')
    
    assert_equal "a1aafafbb5f74fb48312afedb658569b00f4a796", sh(a, 'git rev-parse master')
  end
  
  def test_setup_tracking_on_existing_branch
    # a has access to the simple.git branches
    assert sh(a, 'git branch -a').include?("remotes/origin/xyz")
    assert !sh(a, 'git branch -a').include?("remotes/origin/abc")
    
    # b does not
    assert !sh(b, 'git branch -a').include?("remotes/origin/xyz")
    assert !sh(b, 'git branch -a').include?("remotes/origin/abc")
    
    # make a tracking branch on a
    sh(a, 'git branch xyz --track origin/xyz')
    assert sh(a, 'cat .git/config').include?(%Q{[branch "xyz"]\n\tremote = origin\n\tmerge = refs/heads/xyz})
    
    # make a branch on a... it is NOT tracking it's remote, as can be seen in the config
    sh(a, 'git branch abc')
    assert !sh(a, 'cat .git/config').include?('[branch "abc"]')
    
    # now fetch the new branch
    assert !sh(b, 'git branch -a').include?("remotes/origin/abc")
    sh(b, 'git fetch')
    assert sh(b, 'git branch -a').include?("remotes/origin/abc")
    
    # now setup tracking
    sh(b, 'git branch abc --track origin/abc')
    assert sh(b, 'cat .git/config').include?(%Q{[branch "abc"]\n\tremote = origin\n\tmerge = refs/heads/abc})
    
    assert_equal sh(a, 'git rev-parse abc'), sh(b, 'git rev-parse abc')
  end
  
  def test_setup_tracking_on_a_non_existant_branch_fails
    # no branch yet
    assert !sh(a, 'git branch -a').include?("remotes/origin/abc")
    assert !sh(b, 'git branch -a').include?("remotes/origin/abc")
    
    # make a tracking branch on b... fails
    assert_equal "fatal: Not a valid object name: 'origin/abc'.", sh(a, 'git branch abc --track origin/abc')
  end
  
  def path_in(dir)
    Dir.glob("#{dir}/*").collect {|path| File.basename(path) }.sort
  end
  
  def test_checkout_into_an_alternative_working_dir
    index_file = method_root.path(:tmp, "idx")
    work = method_root.path(:tmp, "work")
    FileUtils.mkdir_p(work)
    
    assert_equal ["one", "one.txt", "x", "x.txt"], path_in(a)
    assert_equal [], path_in(work)
    assert sh(a, "git ls-files --stage").include?("x.txt")
    
    sh(a, "git read-tree --index-output='#{index_file}' c6746dd1882d772e540342f8e180d3125a9364ad")
    sh(a, "git checkout-index -a", 'GIT_INDEX_FILE' => index_file, 'GIT_WORK_TREE' => work)
    
    assert_equal ["one", "one.txt", "x", "x.txt"], path_in(a)
    assert_equal ["one", "one.txt"], path_in(work)
    
    assert sh(a, "git ls-files --stage").include?("x.txt")
    assert !sh(a, "git ls-files --stage", 'GIT_INDEX_FILE' => index_file).include?("x.txt")
  end
  
  def test_fetch_and_manually_merge_changes
    original = sh(a, 'git rev-parse master')
    
    method_root.prepare(a, "alpha") {|io| io << "alpha content" }
    sh(a, 'git add .')
    sh(a, 'git commit -m "added alpha"')
    alpha = sh(a, 'git rev-parse master')
    
    method_root.prepare(a, "beta") {|io| io << "beta content" }
    sh(a, 'git add .')
    sh(a, 'git commit -m "added beta"')
    beta = sh(a, 'git rev-parse master')
    
    a_master = sh(a, 'git rev-parse master')
    b_master = sh(b, 'git rev-parse master')
    assert original != a_master
    assert original == b_master
    
    assert_equal a_master, File.read(method_root.path(a, ".git/refs/heads/master")).chomp("\n")
    assert_equal false, File.exists?(method_root.path(b, ".git/refs/remotes/origin/master"))
    
    sh(b, 'git fetch origin')
    
    expected = "#{beta}\t\tbranch 'master' of #{a}\n"
    assert_equal expected, File.read(method_root.path(b, ".git/FETCH_HEAD"))
    assert_equal "ref: refs/heads/master\n", File.read(method_root.path(b, ".git/HEAD"))
    
    assert_equal a_master, File.read(method_root.path(b, ".git/refs/remotes/origin/master")).chomp("\n")
    
    assert_equal "+ #{alpha}\n+ #{beta}", sh(b, "git cherry #{b_master} #{a_master}")
    assert_equal original, sh(b, "git merge-base #{b_master} #{a_master}")
    
    idx = method_root.prepare(:tmp, 'idx')
    sh(b, "git read-tree --index-output='#{idx}' #{b_master} #{a_master}")
    
    sh(c, 'git pull origin')
    c_master = sh(c, 'git rev-parse master')
    assert a_master == c_master
    assert b_master != c_master
    
    assert_equal sh(c, "git ls-files --stage"), sh(b, "GIT_INDEX_FILE='#{idx}' git ls-files --stage")
    assert_equal sh(c, "git write-tree"), sh(b, "GIT_INDEX_FILE='#{idx}' git write-tree")
    
    b_master = sh(b, 'git rev-parse master')
    c_master = sh(c, 'git rev-parse master')
    
    assert b_master != c_master
  end
  
  def test_manual_3_way_merge
    # changes in b
    method_root.prepare(b, "alpha.txt") {|io| io << "alpha content" }
    sh(b, 'git add alpha.txt')
    sh(b, 'git commit -m "added alpha"')
  
    method_root.prepare(b, "alpha/beta.txt") {|io| io << "beta content" }
    sh(b, 'git add alpha/beta.txt')
    sh(b, 'git commit -m "added beta"')
    
    sh(b, 'git rm alpha.txt')
    sh(b, 'git rm one/two.txt')
    sh(b, 'git rm one/two/three.txt')
    sh(b, 'git commit -m "removed alpha, two, and three"')
    
    # changes in c
    method_root.prepare(c, "alpha/beta/gamma.txt") {|io| io << "gamma content" }
    sh(c, 'git add alpha/beta/gamma.txt')
    sh(c, 'git rm one.txt')
    sh(c, 'git rm one/two/three.txt')
    sh(c, 'git commit -m "add and remove files"')
    
    # push back b
    sh(b, 'git push origin')
    
    # push back c (fails)
    assert sh(c, 'git push origin').include?('! [rejected]        master -> master (non-fast forward)')
    
    # manual merge c
    sh(c, 'git fetch origin')
    tree1 = sh(c, "git merge-base master origin/master")
    current_master = sh(c, 'git rev-parse master')
    
    idx = method_root.prepare(:tmp, 'idx')
    changelog = method_root.prepare(:tmp, 'log') {|io| io << "commit message"}
    
    sh(c, "git read-tree -m -i --trivial --aggressive --index-output='#{idx}' #{tree1} master origin/master")
    commit_tree = sh(c, "GIT_INDEX_FILE='#{idx}' git write-tree")
    commit = sh(c, "GIT_INDEX_FILE='#{idx}' git commit-tree #{commit_tree} -p master < #{changelog}")
    
    current_log = sh(c, "git log --pretty=oneline")
    assert current_log.index(current_master) == 0
    assert !current_log.include?(commit)
    
    assert sh(c, "git log --pretty=oneline #{commit}").index(commit) == 0
    
    # current c
    assert File.exists?(method_root.path(c, "one/two.txt"))
    assert !File.exists?(method_root.path(c, "alpha/beta.txt"))
    assert !File.exists?(method_root.path(c, "one.txt"))
    assert File.exists?(method_root.path(c, "alpha/beta/gamma.txt"))
    
    # manually merged c
    sh(c, "git checkout #{commit}")
    sh(c, "git reset --hard #{commit}")
    
    assert !File.exists?(method_root.path(c, "one/two.txt"))
    assert File.exists?(method_root.path(c, "alpha/beta.txt"))
    assert !File.exists?(method_root.path(c, "one.txt"))
    assert File.exists?(method_root.path(c, "alpha/beta/gamma.txt"))
    
    assert_equal "beta content", File.read(method_root.path(c, "alpha/beta.txt"))
    assert_equal "gamma content", File.read(method_root.path(c, "alpha/beta/gamma.txt"))
  end
end