require 'json'
require 'gitgo/git'
require 'gitgo/index'
require 'gitgo/repo/utils'

module Gitgo
  class Repo
    class << self
      def init(path, options={})
        git = Git.init(path, options)
        idx = Index.new git.path(Git::DEFAULT_DIR, 'index', git.branch)
        new(GIT => git, IDX => idx)
      end
    end
    include Utils
    
    GIT = 'gitgo.git'
    IDX = 'gitgo.idx'
    
    YEAR = /\A\d{4,}\z/
    MMDD = /\A\d{4}\z/
    
    attr_reader :git
    attr_reader :idx
    
    def initialize(env)
      @git = env[GIT]
      @idx = env[IDX]
    end
    
    def head
      git.head
    end
    
    def author
      git.author
    end
    
    def resolve(sha)
      git.resolve(sha)
    end
    
    def [](sha)
      read(sha)
    end
    
    def store(attrs={}, date=Time.now)
      sha = git.set(:blob, JSON.generate(attrs))
      
      path = date.utc.strftime("%Y/%m%d/#{sha}")
      git[path] = sha.to_sym
      
      sha
    end
    
    def read(sha)
      begin
        JSON.parse(git.get(:blob, sha).data)
      rescue JSON::ParserError, Errno::EISDIR
        nil
      end
    end
    
    def link(parent, child)
      if parent == child
        raise "cannot link to self: #{parent} -> #{child}"
      end
      
      current = linkage(parent, child)
      if current && current != empty_sha
        raise "cannot link to an update: #{parent} -> #{child}"
      end
      
      git[sha_path(parent, child)] = empty_sha.to_sym
      self
    end
    
    def update(old_sha, new_sha)
      if old_sha == new_sha
        raise "cannot update with self: #{old_sha} -> #{new_sha}"
      end
      
      if linked?(old_sha, new_sha)
        raise "cannot update with a child: #{old_sha} -> #{new_sha}"
      end
      
      if update?(new_sha)
        raise "cannot update with an update: #{old_sha} -> #{new_sha}"
      end
      
      git[sha_path(old_sha, new_sha)] = old_sha.to_sym
      git[sha_path(new_sha, new_sha)] = old_sha.to_sym
      self
    end
    
    def linkage(parent, child)
      links = git.tree.subtree(sha_path(parent))
      return nil unless links
      
      mode, sha = links[child]
      sha
    end
    
    def linked?(parent, child)
      linkage(parent, child) == empty_sha
    end
    
    def original(sha)
      linkage(sha, sha) || sha
    end
    
    def original?(sha)
      original(sha) == sha
    end
    
    def update?(sha)
      linkage(sha, sha) ? true : false
    end
    
    def each_link(sha)
      links = git.tree.subtree(sha_path(sha)) || {}
      links.each_pair do |link, (mode, ref)|
        # sha == link (parent == child): indicates back reference to origin
        unless sha == link
          
          # sha == ref (parent == ref): indicates update
          yield(link, sha == ref)
        end
      end
    end
    
    def children(parent)
      children = original?(parent) ? [] : children(original(parent))
      each_link(parent) do |link, update|
        children << link unless update
      end
      
      children
    end

    def updates(sha)
      updates = []
      each_link(sha) do |link, update|
        updates << link if update
      end
      updates
    end
    
    def updated?(sha)
      each_link(sha) do |link, update|
        return true if update
      end
      false
    end

    def tree(sha, &block)
      tree = collect_tree(sha)
      tree.values.each do |children|
        next unless children
      
        children.flatten! 
        children.sort!(&block)
      end
      tree
    end

    # Yields the sha of each document in the repo, ordered by date (with day
    # resolution), regardless of whether they are indexed or not.
    def each
      years = git[[]] || []
      years.sort!
      years.reverse_each do |year|
        next unless year =~ YEAR

        mmdd = git[[year]] || []
        mmdd.sort!
        mmdd.reverse_each do |mmdd|
          next unless mmdd =~ MMDD

          # y,md need to be iterated in reverse to correctly sort by
          # date; this is not the case with the unordered shas
          git[[year, mmdd]].each do |sha|
            yield(sha)
          end
        end
      end
    end
  
    def diff(b, a=head)
      case
      when a == b || a.nil?
        []
      when b.nil?
        diff = []
        git.ls_tree(a).each do |path|
          next unless path =~ /^\d{4}\/\d{4}\/(.{40})$/
          diff << $1
        end
        diff
      else
        git.diff_tree(a, b)['A']
      end
    end
    
    def commit(msg)
      git.commit(msg)
    end
    
    def commit!(msg)
      git.commit!(msg)
    end
    
    protected
  
    # Returns the sha for an empty string, and ensures the corresponding
    # object is set in the repo.
    def empty_sha
      @empty_sha ||= git.set(:blob, "")
    end
  
     # a recursive helper method to collect a tree of parent-child links
    def collect_tree(node, siblings=[], tree={nil => siblings}, visited=[]) # :nodoc:
      circular = visited.include?(node)
      visited.push node
    
      if circular
        raise "circular link detected:\n  #{visited.join("\n  ")}\n"
      end
    
      children = []
      tree[node] = children
    
      # traverse the linked children.  if the child is an alias for node, then
      # collect the child as a sibling and remove node from the tree.
      # otherwise, collect the child into children.
      each_link(node) do |child, replacement|
        if replacement
          collect_tree(child, siblings, tree, visited)
          tree[child] << children
          tree[node] = nil
        else
          collect_tree(child, children, tree, visited)
        end
      end
    
      if tree[node]
        siblings << node
      end
    
      visited.pop
      tree
    end
  end
end