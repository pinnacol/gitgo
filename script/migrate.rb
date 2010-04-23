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

a = Gitgo::Repo.init(path, :branch => src)
b = Gitgo::Repo.init(path, :branch => target)

origins = []
others = []
a.scope do
  a.each do |sha|
    doc = Gitgo::Document[sha]
    if doc.origin?
      origins << sha
    else
      others << sha
    end
  end
end

def sha_path(sha, *paths)
  paths.unshift sha[2,38]
  paths.unshift sha[0,2]
  paths
end

DEFAULT_MODE  = '100644'.to_sym
UPDATE_MODE   = '100640'.to_sym

empty_sha = b.git.set(:blob, "")
origins.each do |sha|
  b.git[sha_path(sha, empty_sha)] = [DEFAULT_MODE, sha]
end

(origins + others).each do |source|
  a.each_link(source) do |target, is_update|
    b.git[sha_path(source, target)] = [is_update ? UPDATE_MODE : DEFAULT_MODE, target]
  end
end

b.commit!("Migrated to Gitgo-0.3.0 storage. (was #{a.git.head})")