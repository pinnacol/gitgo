#!/usr/bin/env ruby

# Run using an installed gitgo-0.2.0
#
# == Usage
#
# % ruby -rubygems migrate.rb REPO SOURCE_BRANCH TARGET_BRANCH
#

require 'gitgo'

path, src, target = ARGV
unless path && src && target
  require 'rdoc/usage'
  RDoc.usage_no_exit
  raise "missing path, source, or target"
end

a = Gitgo::Repo.init(path, :branch => src).git
b = Gitgo::Repo.init(path, :branch => target).git

a.tree.flatten.each_pair do |path, entry|
  b[path] = entry
end
b.commit!("Migtrated to Gitgo-0.3.1 storage. (was #{a.head})")