require 'json'
require 'gitgo/git'
require 'gitgo/index'
require 'gitgo/repo/graph'
require 'gitgo/repo/utils'

module Gitgo
  # No merge conflict (a != b != c)
  #          
  #   A (link a -> b) {a => b()}
  #   B (link a -> c) {a => c()}
  #             
  #   A (link a -> b)   {a => b()}
  #   B (update a -> c) {a => c(a), c => c(a)}
  #        
  #   A (update a -> b) {a => b(a), b => b(a)}
  #   B (update a -> c) {a => c(a), c => c(a)}
  #
  # Merge conflict if (a != b != c):
  #          
  #   A (link a -> b)   {a => b()}
  #   B (update a -> b) {a => b(a), b => b(a)}
  #             
  #   A (update a -> b) {a => b(), b => b(a)}
  #   B (update c -> b) {c => b(), b => b(c)}
  #    
  # These conflicts are prevented within a given repo (ie A == B), and will
  # normally not happen remotely because it would require independent
  # generation of the same 'b' document.  Given that documents have a
  # timestamp and an author, this is unlikely, but care should be taken to
  # make sure the same document will not be generated twice and moreover that
  # existing documents cannot be re-linked or re-assigned as an update after
  # creation.
  #
  # Note too that conflicts can arise if (a == b); no linking or updating with
  # self is allowed.
  #
  #   A (link a -> a)   {a => a()}
  #   B (update a -> a) {a => a(a)}
  #
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
    
    def author
      git.author
    end
    
    def resolve(sha)
      git.resolve(sha) rescue sha
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
    
    # Returns true if the two shas are linked as parent and child.
    def linked?(parent, child)
      linkage(parent, child) == empty_sha
    end
    
    def original?(sha)
      original(sha) == sha
    end
    
    def update?(sha)
      previous(sha) ? true : false
    end
    
    def updated?(sha)
      each_link(sha) do |link, update|
        return true if update
      end
      false
    end
    
    def current?(sha)
      each_link(sha) do |link, update|
        return false if update
      end
      true
    end
    
    def tail?(sha)
      each_link(sha) do |link, update|
        return false unless update
      end
      true
    end
    
    def links(parent, target=[])
      if update?(parent)
        links(previous(parent), target)
      end
      
      each_link(parent) do |link, update|
        target << link unless update
      end
      
      target
    end
    
    def original(sha)
      previous = self.previous(sha)
      previous ? original(previous) : sha
    end
    
    def previous(sha)
      linkage(sha, sha)
    end
    
    def updates(sha)
      updates = []
      each_link(sha) do |link, update|
        updates << link if update
      end
      updates
    end
    
    def current(sha, target=[])
      updated = false
      each_link(sha) do |link, update|
        if update
          current(link, target)
          updated = true
        end
      end
      
      unless updated
        target << sha
      end
      
      target
    end
    
    def each_link(sha, include_back_reference=false)
      links = git.tree.subtree(sha_path(sha))
      
      links.each_pair do |link, (mode, ref)|
        if sha == link
          # sha == link (parent == child): indicates back reference to origin
          yield(ref, nil) if include_back_reference
        else
          # sha == ref (parent == ref): indicates update
          yield(link, sha == ref)
        end
      end if links
      
      self
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
    
    def graph(sha)
      Graph.new(self, sha)
    end
    
    def rev_list(sha)
      git.rev_list(sha)
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
    def empty_sha # :nodoc:
      @empty_sha ||= git.set(:blob, "")
    end
  end
end