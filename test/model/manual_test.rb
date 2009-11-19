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
  
  def with_env(env={})
    overrides = {}
    begin
      ENV.keys.each do |key|
        if key =~ /^GIT_/
          overrides[key] = ENV.delete(key)
        end
      end

      env.each_pair do |key, value|
        overrides[key] ||= nil
        ENV[key] = value
      end

      yield
    ensure
      overrides.each_pair do |key, value|
        if value
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end
  
  def sh(dir, cmd)
    with_env do
      Dir.chdir(dir) do
        puts "% #{cmd}" if ENV['DEBUG'] == 'true'
        path = method_root.prepare(:tmp, 'stdout')
        system("#{cmd} > '#{path}' 2>&1")

        output = File.exists?(path) ? File.read(path) : nil
        puts output if ENV['DEBUG'] == 'true'
        output.chomp
      end
    end
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
    
    sh(b, 'git fetch origin')
    
    expected = "#{beta}\t\tbranch 'master' of /Users/Simon/Documents/Gems/gitgo/test/model/manual/#{method_name}/tmp/a\n"
    assert_equal expected, File.read(method_root.path(b, ".git/FETCH_HEAD"))
    assert_equal "ref: refs/heads/master\n", File.read(method_root.path(b, ".git/HEAD"))
    
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