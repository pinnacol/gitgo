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
    n_max = options[:n] || 4
    
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
        puts "%d-%d\t%.2ds\t%.2d post/s\t%05d kb\t%03.2d kb/post" % [min, max, split, m.to_f/split, size, size.to_f/total]
      end
    end
  end
  
  # 0-19        1.050000   0.170000   1.220000 (  1.255800)
  # 20-39       2.580000   0.290000   2.870000 (  2.885843)
  # 40-59       4.150000   0.450000   4.600000 (  4.675210)
  # 60-79       5.760000   0.600000   6.360000 (  6.535442)
  # 0-19  01s 16 post/s 00936 kb   46 kb/post
  # 20-39 02s 06 post/s 01816 kb   45 kb/post
  # 40-59 04s 04 post/s 02696 kb   44 kb/post
  # 60-79 06s 03 post/s 03580 kb   44 kb/post
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
  
  # test_create_speed_with_gc(IssuesBenchmark)
  #                 user     system      total        real
  # 0-19        1.060000   0.170000   1.230000 (  1.314751)
  # gc          0.010000   0.010000   0.020000 (  0.205772)
  # 20-39       2.310000   0.280000   2.590000 (  2.618350)
  # gc          0.000000   0.020000   0.020000 (  0.221586)
  # 40-59       3.520000   0.340000   3.860000 (  3.879119)
  # gc          0.000000   0.010000   0.020000 (  0.240985)
  # 60-79       4.810000   0.390000   5.200000 (  5.230521)
  # gc          0.010000   0.010000   0.020000 (  0.261413)
  # 80-99       6.190000   0.460000   6.650000 (  6.837929)
  # gc          0.000000   0.010000   0.020000 (  0.279122)
  # 100-119     7.560000   0.500000   8.060000 (  8.281517)
  # gc          0.010000   0.020000   0.030000 (  0.280893)
  # 120-139     8.390000   0.550000   8.960000 (  9.448215)
  # gc          0.000000   0.010000   0.010000 (  0.352383)
  # 140-159     8.910000   0.600000   9.510000 (  9.756089)
  # gc          0.010000   0.010000   0.020000 (  0.469065)
  # 160-179     9.900000   0.630000  10.530000 ( 10.727350)
  # gc          0.010000   0.020000   0.030000 (  0.466876)
  # 180-199    10.860000   0.650000  11.510000 ( 11.731084)
  # gc          0.010000   0.020000   0.030000 (  0.807143)
  # 0-19  01s 16 post/s 00084 kb   04 kb/post
  # 20-39 02s 07 post/s 00112 kb   02 kb/post
  # 40-59 03s 05 post/s 00132 kb   02 kb/post
  # 60-79 05s 03 post/s 00156 kb   01 kb/post
  # 80-99 06s 03 post/s 00176 kb   01 kb/post
  # 100-119 08s 02 post/s 00204 kb   01 kb/post
  # 120-139 08s 02 post/s 00224 kb   01 kb/post
  # 140-159 09s 02 post/s 00252 kb   01 kb/post
  # 160-179 10s 01 post/s 00272 kb   01 kb/post
  # 180-199 11s 01 post/s 00308 kb   01 kb/post

  # This is the summary for n => 10.  My computer was really sweating at the
  # end and I can't think this is normal.  It's just not all that much to be
  # creating.  I don't like that both the time is continually increasing.
  #
  # === Errors
  #
  # Sometimes this errors out with:
  #
  # test_create_speed_with_gc(IssuesBenchmark):
  # Errno::EMFILE: Too many open files
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/grit-2.0.0/lib/open3_detach.rb:7:in `pipe'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/grit-2.0.0/lib/open3_detach.rb:7:in `popen3'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/grit-2.0.0/lib/grit/git.rb:248:in `sh'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/grit-2.0.0/lib/grit/git.rb:240:in `run'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/grit-2.0.0/lib/grit/git.rb:215:in `method_missing'
  #     /Users/simonchiang/Documents/Gems/gitgo/lib/gitgo/repo.rb:610:in `gc'
  #     ./test/benchmark/issues_benchmark.rb:91:in `test_create_speed_with_gc'
  #     /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/benchmark.rb:293:in `measure'
  #     /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/benchmark.rb:380:in `report'
  #     ./test/benchmark/issues_benchmark.rb:90:in `test_create_speed_with_gc'
  #     ./test/benchmark/issues_benchmark.rb:43:in `call'
  #     ./test/benchmark/issues_benchmark.rb:43:in `profile_test'
  #     ./test/benchmark/issues_benchmark.rb:32:in `collect'
  #     ./test/benchmark/issues_benchmark.rb:32:in `profile_test'
  #     /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/benchmark.rb:177:in `benchmark'
  #     /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/lib/ruby/1.8/benchmark.rb:207:in `bm'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/tap-test-0.2.0/lib/tap/test/subset_test.rb:209:in `benchmark_test'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/tap-test-0.2.0/lib/tap/test/subset_test.rb:178:in `subset_test'
  #     /Users/simonchiang/Documents/Gems/gitgo/vendor/gems/gems/tap-test-0.2.0/lib/tap/test/subset_test.rb:206:in `benchmark_test'
  #     ./test/benchmark/issues_benchmark.rb:31:in `profile_test'
  #     ./test/benchmark/issues_benchmark.rb:95:in `test_create_speed_with_gc'
  # 
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
  
  # test_parts_of_create(IssuesBenchmark)
  #                 user     system      total        real
  # 0-19        0.730000   0.130000   0.860000 (  0.899290)
  # 20-39       1.640000   0.200000   1.840000 (  1.861271)
  # 40-59       2.490000   0.280000   2.770000 (  2.860056)
  # 60-79       3.370000   0.360000   3.730000 (  3.917105)
  # 80-99       4.220000   0.440000   4.660000 (  4.926546)
  # 100-119     5.150000   0.510000   5.660000 (  5.864612)
  # 120-139     6.000000   0.590000   6.590000 (  6.882233)
  # 140-159     6.880000   0.660000   7.540000 (  7.763211)
  # 160-179     7.740000   0.740000   8.480000 (  8.821682)
  # 180-199     8.510000   0.790000   9.300000 (  9.572923)
  # 
  # commit
  #   000-019: 0.7734s (0.0387 x/s)   0.0000
  #   020-039: 1.6340s (0.0817 x/s) + 0.8606
  #   040-059: 2.5972s (0.1299 x/s) + 0.9632
  #   060-079: 3.5986s (0.1799 x/s) + 1.0014
  #   080-099: 4.4205s (0.2210 x/s) + 0.8219
  #   100-119: 5.2701s (0.2635 x/s) + 0.8496
  #   120-139: 5.8085s (0.2904 x/s) + 0.5384
  #   140-159: 6.9610s (0.3480 x/s) + 1.1525
  #   160-179: 7.7289s (0.3864 x/s) + 0.7680
  #   180-199: 8.3390s (0.4169 x/s) + 0.6100
  # create
  #   000-019: 0.0991s (0.0050 x/s)   0.0000
  #   020-039: 0.1545s (0.0077 x/s) + 0.0554
  #   040-059: 0.1956s (0.0098 x/s) + 0.0412
  #   060-079: 0.2360s (0.0118 x/s) + 0.0403
  #   080-099: 0.3459s (0.0173 x/s) + 0.1099
  #   100-119: 0.3892s (0.0195 x/s) + 0.0434
  #   120-139: 0.7913s (0.0396 x/s) + 0.4020
  #   140-159: 0.4773s (0.0239 x/s) - 0.3140
  #   160-179: 0.8751s (0.0438 x/s) + 0.3979
  #   180-199: 0.8205s (0.0410 x/s) - 0.0547
  # link
  #   000-019: 0.0162s (0.0008 x/s)   0.0000
  #   020-039: 0.0628s (0.0031 x/s) + 0.0467
  #   040-059: 0.0575s (0.0029 x/s) - 0.0053
  #   060-079: 0.0732s (0.0037 x/s) + 0.0157
  #   080-099: 0.1504s (0.0075 x/s) + 0.0772
  #   100-119: 0.1953s (0.0098 x/s) + 0.0449
  #   120-139: 0.2718s (0.0136 x/s) + 0.0765
  #   140-159: 0.3143s (0.0157 x/s) + 0.0425
  #   160-179: 0.2074s (0.0104 x/s) - 0.1068
  #   180-199: 0.4030s (0.0201 x/s) + 0.1955
  # update
  #   000-019: 0.0102s (0.0005 x/s)   0.0000
  #   020-039: 0.0096s (0.0005 x/s) - 0.0007
  #   040-059: 0.0093s (0.0005 x/s) - 0.0003
  #   060-079: 0.0089s (0.0004 x/s) - 0.0004
  #   080-099: 0.0093s (0.0005 x/s) + 0.0005
  #   100-119: 0.0096s (0.0005 x/s) + 0.0002
  #   120-139: 0.0102s (0.0005 x/s) + 0.0006
  #   140-159: 0.0102s (0.0005 x/s) + 0.0000
  #   160-179: 0.0097s (0.0005 x/s) - 0.0005
  #   180-199: 0.0101s (0.0005 x/s) + 0.0003
  #
  # == Observations
  # Create and link both grow, and at a pretty astonishing rate.  They aren't the
  # biggest, but clearly they will grow out of hand.  Commit is the real bad guy,
  # increasing and large already.
  # 
  def test_parts_of_create
    author = repo.author
    date = Time.now
    idx = app.prototype.idx
    
    m = 20
    n = 3
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
            timer(:commit, splits) { repo.commit("added issue #{issue}") }
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