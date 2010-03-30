require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/gempackagetask'

ENV['GEMSPEC'] = 'gitgo.gemspec'

#
# Gem specification
#

def gemspec
  data = File.read(ENV['GEMSPEC'])
  spec = nil
  Thread.new { spec = eval("$SAFE = 3\n#{data}") }.join
  spec
end

Rake::GemPackageTask.new(gemspec) do |pkg|
  pkg.need_tar = true
end

desc 'Prints the gemspec manifest.'
task :print_manifest do
  # collect files from the gemspec, labeling 
  # with true or false corresponding to the
  # file existing or not
  files = gemspec.files.inject({}) do |files, file|
    files[File.expand_path(file)] = [File.exists?(file), file]
    files
  end
  
  # gather non-rdoc/pkg files for the project
  # and add to the files list if they are not
  # included already (marking by the absence
  # of a label)
  Dir.glob("**/*").each do |file|
    next if file =~ /^(rdoc|pkg|backup|test|fixtures|design|vendor)/ || File.directory?(file)
    
    path = File.expand_path(file)
    files[path] = ["", file] unless files.has_key?(path)
  end
  
  # sort and output the results
  files.values.sort_by {|exists, file| file }.each do |entry| 
    puts "%-5s %s" % entry
  end
end

#
# Documentation tasks
#

desc 'Generate documentation.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  spec = gemspec
  
  rdoc.rdoc_dir = 'rdoc'
  rdoc.options.concat(spec.rdoc_options)
  rdoc.rdoc_files.include( spec.extra_rdoc_files )
  
  files = spec.files.select {|file| file =~ /^lib.*\.rb$/}
  rdoc.rdoc_files.include( files )
end

#
# Management tasks
#

desc "Checkout test fixtures"
task :checkout_fixtures do 
  fixtures = Dir.glob("test/fixtures/*.git")
  fixtures_dir = File.dirname(__FILE__) + "/fixtures"
  
  fixtures.each do |fixture|
    target = File.join(fixtures_dir, File.basename(fixture).chomp('.git'))
    puts "checking out: #{fixture}"
    `git clone '#{fixture}' '#{target}'`
  end
end

def tick
  @tick ||= 0
  @tick += 1
  if @tick == 100
    print "."
    $stdout.flush
    @tick = 0
  end
end

# 1000 commits
#  800 on master
#  100 on dev1
#  100 on dev2
#
# pre-gc:  12.4 MB on disk (215,812 bytes)
# post-gc: 360 KB on disk (284,433 bytes) 
task :build_fixture => :bundle do
  require 'vendor/gems/environment'
  require 'gitgo/repo'
  
  unless File.exists?("fixtures/large")
    repo = Gitgo::Repo.init("fixtures/large", :branch => "master")
    0.upto(799).each do |n|
      str = "%03d" % n
      repo.add("at" => str).commit("commit #{str}")
      tick
    end
  
    repo.checkout("dev1", "fixtures/large", :b => true)
    800.upto(899) do |n|
      str = "%03d" % n
      repo.add("at" => str).commit("commit #{str}")
      tick
    end
  
    repo.checkout("master", "fixtures/large")
    repo.checkout("dev2", "fixtures/large", :b => true)
    900.upto(999) do |n|
      str = "%03d" % n
      repo.add("at" => str).commit("commit #{str}")
      tick
    end
    puts
  end
end

#
# Dependency tasks
#

desc 'Bundle dependencies'
task :bundle do
  output = `bundle check 2>&1`
  
  unless $?.to_i == 0
    puts output
    puts "bundle install 2>&1"
    system "bundle install 2>&1"
    puts
  end
end

#
# Test tasks
#

desc 'Default: Run tests.'
task :default => :test

desc 'Run the tests'
task :test => ['test:gitgo', 'test:model']

desc 'Run the cc tests'
task :cc => :test

def run_tests(tests)
  tests = tests.select {|path| File.file?(path) }
  cmd = ['ruby', "-w", "-e", "ARGV.dup.each {|test| load test}"] + tests
  sh(*cmd)
end

namespace :test do
  desc 'Run all the tests'
  task :all => ['test:gitgo', 'test:benchmark']
  
  desc 'Run gitgo tests'
  task :gitgo => :bundle do
    pattern = ENV['PATTERN'] || "**/*_test.rb"
    run_tests Dir.glob("test/gitgo/#{pattern}")
  end
  
  task :git => :bundle do
    run_tests Dir.glob("test/gitgo/git/*_test.rb") + ["test/gitgo/git_test.rb"]
  end
  
  task :index => :bundle do
    run_tests Dir.glob("test/gitgo/index/*_test.rb") + ["test/gitgo/index_test.rb"]
  end
  
  task :repo => :bundle do
    run_tests ["test/gitgo/repo_test.rb"] + Dir.glob("test/gitgo/repo/*_test.rb")
  end
  
  task :document => :bundle do
    run_tests ["test/gitgo/document_test.rb"] + Dir.glob("test/gitgo/document/*_test.rb")
  end
  
  task :documents => :bundle do
    run_tests Dir.glob("test/gitgo/documents/*_test.rb")
  end
  
  task :controllers => :bundle do
    run_tests ["test/gitgo/controller_test.rb"] + Dir.glob("test/gitgo/controllers/*_test.rb")
  end
  
  task :helpers => :bundle do
    run_tests Dir.glob("test/gitgo/helper/*_test.rb")
  end
  
  desc 'Run data model tests'
  task :model => :bundle do
    pattern = ENV['PATTERN'] || "**/*_test.rb"
    run_tests Dir.glob("test/model/#{pattern}")
  end
  
  desc 'Run benchmark tests'
  task :benchmark => :bundle do
    ENV['BENCHMARK'] = "true"
    pattern = ENV['PATTERN'] || "**/*_benchmark.rb"
    run_tests Dir.glob("test/benchmark/#{pattern}")
  end
end
