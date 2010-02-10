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
    
    def create(attrs={}, date=Time.now)
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
        raise "cannot link to self"
      end
      
      git[sha_path(parent, child)] = empty_sha
      self
    end
  
    def update(old_sha, new_sha)
      unless old_sha == new_sha
        git[sha_path(old_sha, new_sha)] = old_sha.to_sym
      end
      
      self
    end
    
    def commit(msg)
      git.commit(msg)
    end
    
    def commit!(msg)
      git.commit!(msg)
    end
    
    # Returns an array of parents that link to the child.  Note this is a very
    # expensive operation because it fully expands the in-memory working tree.
    def parents(child)
      # seek /ab/xyz/sha where sha == child
      parents = []
      git.tree.each_tree(true) do |ab, ab_tree|
        next if ab.length != 2
      
        ab_tree.each_tree(true) do |xyz, xyz_tree|
          next if xyz.length != 38
        
          if xyz_tree.keys.any? {|sha| sha.to_s == child }
            parents << "#{ab}#{xyz}"
          end
        end
      end
      parents
    end

    # Returns an array of children linked to the parent.
    def children(parent)
      children = []
      each_link(parent) do |child, update|
        children << child unless update
      end
      children
    end

    def updates(sha)
      updates = []
      each_link(sha) do |child, update|
        updates << child if update
      end
      updates
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

    def list_tree(sha, &block)
      list_tree = flatten tree(sha, &block)
      list_tree = collapse(list_tree[nil])
      list_tree.shift
      list_tree
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
    
    protected
  
    # Returns the sha for an empty string, and ensures the corresponding
    # object is set in the repo.
    def empty_sha
      @empty_sha ||= git.set(:blob, "").to_sym
    end
  
    # yields each linkage to the specified document with a flag indicating
    # whether the link indicates a update
    def each_link(sha) # :nodoc:
      links = git.tree.subtree(sha_path(sha)) || {}
      links.each_pair do |child, (mode, ref)|
        yield(child, sha == ref)
      end
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