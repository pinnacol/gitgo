require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/issues'
require 'benchmark'

class IssuesBenchmark < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  include Benchmark
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root[:tmp], :bare => true)
    app.set :repo, @repo
    app.set :secret, "123"
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Issues
  end
  
  def profile_test(options={})
    action = options[:action]
    pre = options[:pre]
    post = options[:post]
    m = options[:m] || 20
    n_max = options[:n] || 4
    
    bm(20) do |x|
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
        
        io = IO.popen("du -sk #{repo.path}")
        io.read =~ /(\d+)/
        io.close
        size = $1
      
        [min, max, time.total, size]
      end.each do |min, max, time, size|
        puts "%d-%d\t%.2ds\t%.2d post/s\t%d kb\t%.2d kb/post" % [min, max, time, m.to_f/time, size, size.to_f/m]
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
        
      # unless last_response.redirect?
      #   flunk last_response.body
      # end
      now += 86400 # one day
    end
    
    gc = lambda do |x|
      x.report("gc") do
        IO.popen("GIT_DIR='#{repo.path}' git gc") do |io|
          puts
          puts io.read
          print " " * 20
        end
      end
    end
    
    profile_test(:action => action, :post => gc)
  end
end