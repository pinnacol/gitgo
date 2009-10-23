require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/gempackagetask'

#
# Gem specification
#

def gemspec
  data = File.read('gitgo.gemspec')
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
    next if file =~ /^(rdoc|pkg|backup|vendor)/ || File.directory?(file)
    
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

#
# Test tasks
#

desc 'Default: Run tests.'
task :default => :test

task :check_bundle do
  unless File.exists?("vendor/gems/environment.rb")
    puts %Q{
Tests cannot be run until the dependencies have been
bundled.  Use these commands and try again:

  % git submodule init
  % git submodule update
  % gem bundle

}
    exit(1)
  end
end

desc 'Run the tests'
task :test => ['test:model', 'test:gitgo']

namespace :test do
  desc 'Run gitgo tests'
  task :gitgo => :check_bundle do
    pattern = ENV['PATTERN'] || "**/*_test.rb"
    tests = Dir.glob("test/gitgo/#{pattern}").select {|path| File.file?(path) }
    cmd = ['ruby', "-w", '-rvendor/gems/environment.rb', "-e", "ARGV.dup.each {|test| load test}"] + tests
    sh(*cmd)
  end
  
  desc 'Run data model tests'
  task :model => :check_bundle do
    tests = Dir.glob('test/model/**/*_test.rb')
    cmd = ['ruby', "-w", '-rvendor/gems/environment.rb', "-e", "ARGV.dup.each {|test| load test}"] + tests
    sh(*cmd)
  end
end

desc "Update bundle for CruiseControl"
task :cc_bundle do
  FileUtils.rm_r("vendor/gems") if File.exists?("vendor/gems")
  system("BUNDLE_CC='true' gem bundle")
end

desc 'Run the cc tests'
task :cc => [:cc_bundle, :test]

