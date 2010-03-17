#!/usr/bin/env ruby

# == Description
#
# The repo at 0.1.0 stored documents in a funky YAML format.  Beginning at
# 0.2.0 the repo began storing documents as JSON.  Several details regarding
# links were also changed.  Specifically a document origin (re) is no longer
# stored as the link content, instead the origin is stored in the attributes
#
# This migration script revises the storage format of documents to JSON and
# reassigns all links.  Input a repo path, the branch to migrate, and the
# branch to store new documents. Run this script at commit 19e74cd (so as to
# use a known repo/utils) then manually rename branches as needed.
#
# == Usage
#
#   % ruby script/migrate.rb REPO SOURCE_BRANCH TARGET_BRANCH
#

require "rubygems"
require "bundler"
Bundler.setup(:default)
require 'gitgo'

path, src, target = ARGV
unless path && src && target
  require 'rdoc/usage'
  RDoc.usage_no_exit
  raise "missing path, source, or target"
end

a = Gitgo::Repo.init(path, :branch => src)
b = Gitgo::Repo.init(path, :branch => target)

git = a.git
tree = git.tree

# get origin references
origin = {}
tree.each_pair(true) do |ab, ab_entry|
  ab = ab.to_s
  next unless ab.length == 2
  
  ab_tree = tree.subtree([ab])
  ab_tree.each_pair(true) do |xyz, xyz_entry|
    xyz = xyz.to_s
    
    xyz_tree = ab_tree.subtree([xyz])
    xyz_tree.each_pair(true) do |child, (mode, sha)|
      re = git.get(:blob, sha.to_s).data
      origin[child.to_s] = re unless re.empty?
    end
  end
end

# collect documents
map = {}
docs = {}
a.each do |sha|
  attrs = Gitgo::Repo::Utils.deserialize(git.get(:blob, sha).data)
  
  unless date = attrs['date']
    raise "no date found... #{sha}"
  end
  
  date = Time.at(date).utc
  attrs['date'] = date.iso8601
  docs[sha] = [attrs, date]
end

# store origins first...
origin.values.uniq.each do |sha|
  next if sha.empty?
  
  map[sha] ||= begin
    doc = docs.delete(sha)
    unless doc
      raise "doc gone it: #{sha}"
    end
    
    b.store(*doc)
  end
end

# store docs with mapped origins
docs.each_pair do |sha, (attrs, date)|
  if origin.has_key?(sha)
    attrs['re'] = map[origin[sha]] or raise "no map for origin: #{origin[sha]}"
  end
  map[sha] = b.store(attrs, date)
end

# update links
tree.each_pair(true) do |ab, ab_entry|
  ab = ab.to_s
  next unless ab.length == 2
  
  ab_tree = tree.subtree([ab])
  ab_tree.each_pair(true) do |xyz, xyz_entry|
    xyz = xyz.to_s
    
    xyz_tree = ab_tree.subtree([xyz])
    xyz_tree.each_pair(true) do |child, (mode, sha)|
      parent = "#{ab}#{xyz}"
      unless map.has_key?(parent)
        # parent is not a document -- an artifact of early gitgo storage
        next
      end
      
      unless map.has_key?(child)
        raise "no map for child: #{child}"
      end
      
      b.link(map[parent], map[child])
    end
  end
end

b.commit!("Migrated to Gitgo-0.2.0 storage. (was #{git.head})")