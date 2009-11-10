require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/issues'
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
    Gitgo::Issues
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
        
        io = IO.popen("du -sk #{repo.path}")
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
        
      unless last_response.redirect?
        flunk last_response.body
      end
      now += 86400 # one day
    end
    
    gc = lambda do |x|
      x.report("gc") do
        repo.gc
      end
    end
    
    profile_test(:action => action, :post => gc)
  end
  
  def test_parts_of_create
    author = repo.author
    date = Time.now
    idx = app.prototype.idx
    
    m = 20
    n = 10
    benchmark_test do |x|
      totals = {}
      previous = {}
      (0...n).to_a.collect do |n|
        min = n*m
        max = min + m-1
        splits = {}
        x.report("#{min}-#{max}") do
          min.upto(max) do |i|
            issue = timer(:create, splits) { repo.create("content #{i}", {'author' => author, 'date' => date}) }
            timer(:link, splits)   { repo.link(issue, issue, :dir => app::INDEX) }
            timer(:update, splits) { idx.update(issue) }
            timer(:commit, splits) { repo.commit!("added issue #{issue}") }
            date += 8640
          end
        end
        
        splits.each_pair do |key, array|
          sum = array.inject(0.0) {|sum, i| sum + i}
          avg = sum/m
          
          delta = 0
          if prior_sum = previous[key]
            delta = sum - prior_sum
          end
          
          sign = case
          when delta > 0 then "+"
          when delta < 0 then "-"
          else " "
          end
          
          previous[key] = sum
          (totals[key] ||= []) << "  %03d-%03d: %.4fs (%.4f x/s) #{sign} %.4f" % [min, max, sum, avg, delta.abs]
        end
      end
      
      puts
      totals.keys.sort_by do |key|
        key.to_s
      end.each do |key|
        puts "#{key}"
        puts totals[key].join("\n")
      end
    end
  end
end