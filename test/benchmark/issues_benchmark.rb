require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/controllers/issue'
require 'benchmark'

class IssuesBenchmark < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  acts_as_subset_test
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root[:tmp], :bare => true)
    app.set :repo, @repo
    app.set :secret, "123"
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Controllers::Issue
  end
  
  def tick(n=100)
    @ticks ||= 0
    @ticks += 1
    if @ticks == n
      print "."
      $stdout.flush
      @ticks = 0
    end
  end
  
  def timer(type, splits)
    start = Time.now
    res = yield
    (splits[type] ||= []) << (Time.now - start)
    res
  end
  
  def profile_test(options={})
    action = options[:action]
    pre = options[:pre]
    post = options[:post]
    m = options[:m] || 20
    n_max = options[:n] || 10
    
    benchmark_test do |x|
      total = 0
      (0...n_max).to_a.collect do |n|
        pre.call(x) if pre
        
        min = n*m
        max = min + m-1
        time = x.report("#{min}-#{max}") do
          min.upto(max) do |i|
            action.call(i)
          end
        end
        
        post.call(x) if post
        
        # check the non-disposable additions
        io = IO.popen("du -sk #{repo.path('objects')}")
        io.read =~ /(\d+)/
        io.close
        size = $1
        
        total += m
        [min, max, time.total, size, total]
      end.each do |min, max, split, size, total|
        puts "%d-%d\t%.2fs\t%.2d post/s\t%05d kb\t%03.2d kb/post" % [min, max, split, m.to_f/split, size, size.to_f/total]
      end
    end
  end
  
  def test_create_speed
    now = Time.now
    action = lambda do |i|
      post("/issue", 
        "doc[title]" => "issue #{i}", 
        "doc[date]" => now.to_i,
        "secret" => 123,
        "commit" => "true")
      
      assert last_response.redirect?
      now += 86400 # one day
    end
    
    profile_test(:action => action)
  end
  
  def test_create_speed_with_gc
    now = Time.now
    
    action = lambda do |i|
      post("/issue", 
        "doc[title]" => "issue #{i}", 
        "doc[date]" => now.to_i,
        "secret" => 123,
        "commit" => "true")
        
      assert last_response.redirect?
      now += 86400 # one day
    end
    
    gc = lambda do |x|
      x.report("gc") do
        repo.gc
      end
    end
    
    profile_test(:action => action, :post => gc)
  end
  
  def test_update_speed
    now = Time.now
    post("/issue", 
      "doc[title]" => "issue", 
      "doc[date]" => now.to_i,
      "secret" => 123,
      "commit" => "true")
    
    assert last_response.redirect?
    
    id = File.basename(last_response['Location'])
    now += 86400 # one day
    
    previous = id
    action = lambda do |i|
      put("/issue/#{id}", 
        "content" => "comment #{i}",
        "re[]" => previous,
        "doc[date]" => now.to_i,
        "secret" => 123,
        "commit" => "true")
      
      assert last_response.redirect?, last_response.body
      previous = File.basename(last_response['Location'])
      now += 86400 # one day
    end
    
    profile_test(:action => action)
  end
  
  def test_update_speed_with_gc
    now = Time.now
    post("/issue", 
      "doc[title]" => "issue", 
      "doc[date]" => now.to_i,
      "secret" => 123,
      "commit" => "true")
    
    assert last_response.redirect?
    
    id = File.basename(last_response['Location'])
    now += 86400 # one day
    
    previous = id
    action = lambda do |i|
      put("/issue/#{id}", 
        "content" => "comment #{i}",
        "re[]" => previous,
        "doc[date]" => now.to_i,
        "secret" => 123,
        "commit" => "true")
      
      assert last_response.redirect?, last_response.body
      previous = File.basename(last_response['Location'])
      now += 86400 # one day
    end
    
    gc = lambda do |x|
      x.report("gc") do
        repo.gc
      end
    end
    
    profile_test(:action => action, :post => gc)
  end
  
  def test_index_speed
    now = Time.now
    
    n = 10
    m = 10
    benchmark_test do |x|
      total = 0
      (0...n).to_a.collect do |n|
        time = x.report("@#{n*m}") do
          100.times do
            get("/issue")
          end
        end
        assert last_response.ok?
        
        0.upto(m) do |i|
          post("/issue", 
            "doc[title]" => "issue #{n*m + i}", 
            "doc[date]" => now.to_i,
            "secret" => 123,
            "commit" => "true")

          assert last_response.redirect?
          now += 86400 # one day
        end
        
        [n*m, time.total]
      end.each do |total, split|
        puts "@%.3d issues\t%.2fs\t%.2d index/s" % [total, split, m.to_f/split]
      end
    end
  end
end