require 'json'
require 'gitgo/git'
require 'gitgo/index'
require 'gitgo/repo/graph'
require 'gitgo/repo/utils'

module Gitgo
  # Repo represents the internal data store used by Gitgo. Repos consist of a
  # Git instance for storing documents in the repository, and an Index
  # instance for queries on the documents. The internal workings of Repo are a
  # bit complex; this document provides terminology and details on how
  # documents and linkages are stored.  See Index and Graph for how the stored
  # information is accessed.
  #
  # == Terminology
  #
  # Gitgo documents are hashes of attributes that can be serialized as JSON.
  # The Gitgo::Document model adds structure to these hashes and enforces data
  # validity, but insofar as Repo is concerned, a document is a serializable
  # hash. Documents are linked into a document graph -- a directed acyclic
  # graph (DAG) of document nodes that represent, for example, a chain of
  # comments making a conversation.  A given repo can be thought of as storing
  # multiple DAGs, each made up of multiple documents.
  #
  # The DAGs used by Gitgo are a little weird because they use some nodes to
  # represent revisions, and other nodes to represent the 'current' nodes in a
  # graph (this setup allows documents to be immutable, and thereby to prevent
  # merge conflicts).  
  #
  # Normally a DAG has this conceptual structure:
  #
  #   head
  #   |
  #   parent
  #   |
  #   node
  #   |
  #   child
  #   |
  #   tail
  #
  # By contrast, the DAGs used by Gitgo are structured like this:
  #
  #                           head
  #                           |
  #                           parent
  #                           |
  #   original -> previous -> node -> update -> current version
  #                           |
  #                           child
  #                           |
  #                           tail
  #
  # The extra dimension of updates may be unwound to replace all previous
  # versions of a node with the current version(s), so for example:
  #
  #               a                       a
  #               |                       |
  #               b -> b'    becomes      b'
  #               |                       |
  #               c                       c
  #
  # The full DAG is refered to as the 'convoluted graph' and the current DAG
  # is the 'deconvoluted graph'.  The logic performing the deconvolution is
  # encapsulated in Gitgo::Graph.
  #
  # Parent-child relationships are referred to as links, while previous-update
  # relationships are referred to as updates.  Links and updates are
  # collectively referred to as linkages.  The first member in a linkage
  # (parent/previous) is a source and the second (child/update) is a target.
  #
  # Deletes are supported as a special type of update where the document is
  # updated to itself; these act as a break in the DAG where all subsequent
  # links and updates are omitted.
  #             
  # == Documents and Linkages
  #
  # Documents and linkages are stored on a dedicated git branch in a way that
  # prevents merge conflicts, and allows merges to directly add nodes anywhere
  # in a document graph.  The branch may be checked out and handled like any
  # other git branch, although typically users manage the gitgo branch through
  # Gitgo itself.
  #
  # Individual documents are stored by a date/sha path like this, where sha is
  # the sha of the serialized document (ie it identifies the blob storing the
  # document):
  #
  #   path              mode    blob
  #   YYYY/MMDD/sha     100644  sha
  #
  # The path is meaningful to determine a timeline of activity without
  # examining the contents of any individual document.
  #
  # Linkages similarly incorporate document shas into their path, but split up
  # the source sha into substrings of length 2 and 38 (note that empty sha
  # refers to the sha of an empty file):
  #
  #   path              mode    blob
  #   pa/rent/child     100644  empty_sha
  #   pr/evious/update  100644  previous
  #   de/lete/delete    100644  delete
  #
  # The relationship between the source, target, and blob shas is used to
  # determine the type of linkage involved.  The logic breaks down like so:
  #
  #   source == target   blob         linkage type
  #   no                 empty_sha    link
  #   no                 source       update
  #   yes                target       delete
  #
  # Using this logic, a traveral of the linkages is enough to determine how
  # documents are related, again without loading individual documents into
  # memory.
  #
  # == Implementation Note
  #
  # Repo is organized around an env hash that represents the rack env for a
  # particular request.  Objects used by Repo are cached into env for re-use
  # across multiple requests, when possible.  The 'gitgo.*' constants are used
  # to identify cached objects.
  #
  # Repo knows how to initialize all the objects it uses.  An empty env or a
  # partially filled env may be used to initialize a Repo.
  #
  class Repo
    class << self
      
      # Initializes a new Repo to the git repository at the specified path.
      # Options are the same as for Git.init.
      def init(path, options={})
        git = Git.init(path, options)
        new(GIT => git)
      end
      
      # Sets env as the thread-specific env and returns the currently set env.
      def set_env(env)
        current = Thread.current[ENVIRONMENT]
        Thread.current[ENVIRONMENT] = env
        current
      end
      
      # Sets env for the block.
      def with_env(env)
        begin
          current = set_env(env)
          yield
        ensure
          set_env(current)
        end
      end
      
      # The thread-specific env currently in scope (see set_env).  The env
      # stores all the objects used by a Repo and typically represents the
      # rack-env for a specific server request.
      #
      # Raises an error if no env is in scope.
      def env
        Thread.current[ENVIRONMENT] or raise("no env in scope")
      end
      
      # Returns the current Repo, ie env[REPO].  Initializes and caches a new
      # Repo in env if env[REPO] is not set.
      def current
        env[REPO] ||= new(env)
      end
    end
    include Utils
    
    ENVIRONMENT  = 'gitgo.env'
    PATH         = 'gitgo.path'
    OPTIONS      = 'gitgo.options'
    GIT          = 'gitgo.git'
    IDX          = 'gitgo.idx'
    REPO         = 'gitgo.repo'
    CACHE        = 'gitgo.cache'
    
    # Matches YYYY in a formatted date
    YEAR = /\A\d{4,}\z/
    
    # Matches MMDD in a formatted date
    MMDD = /\A\d{4}\z/
    
    # Matches a link path -- 'ab/xyz/sha'.  After the match:
    #
    #  $1:: ab
    #  $2:: xyz
    #  $3:: sha
    #
    LINK = /^(.{2})\/(.{38})\/(.{40})$/
    
    # Matches a document path -- 'YYYY/MMDD/sha'.  After the match:
    #
    #  $1:: year
    #  $2:: month-day
    #  $3:: sha
    #
    DOCUMENT = /^(\d{4,})\/(\d{4})\/(.{40})$/
    
    # The repo env, typically the same as a request env.
    attr_reader :env
    
    # Initializes a new Repo with the specified env.
    def initialize(env={})
      @env = env
    end
    
    # The gitgo head, ie the head of the branch where gitgo documents are
    # stored.
    def head
      git.head
    end
    
    # The git author, used as the default author for documents with no author.
    def author
      git.author
    end
    
    # Resolves sha (which could be a sha, a short-sha, or treeish) to a full
    # sha.  Returns nil if the sha cannot be resolved.
    def resolve(sha)
      git.resolve(sha) rescue sha
    end
    
    # Returns the path to git repository.  Path is determined from env[PATH],
    # or inferred and set in env from env[GIT].  The default path is Dir.pwd.
    def path
      env[PATH] ||= (env.has_key?(GIT) ? env[GIT].path : Dir.pwd)
    end
    
    # Returns the Git instance set in env[GIT].  If no instance is set then
    # one will be initialized using env[PATH] and env[OPTIONS].
    #
    # Note that given the chain of defaults, git will be initialized to
    # Dir.pwd if the env has no PATH or GIT set.
    def git
      env[GIT] ||= Git.init(path, env[OPTIONS] || {})
    end
    
    # Returns the Index instance set in env[IDX].  If no instance is set then
    # one will be initialized under the git working directory, specific to the
    # git branch.  For instance:
    #
    #   .git/gitgo/index/branch
    #
    def idx
      env[IDX] ||= Index.new(File.join(git.work_dir, 'index', git.branch), Git::Tree.string_table)
    end
    
    # Returns or initializes a self-populating cache of attribute hashes in
    # env[CACHE]. Attribute hashes are are keyed by sha.
    def cache
      env[CACHE] ||= Hash.new {|hash, sha| hash[sha] = read(sha) }
    end
    
    # Returns the cached attrs hash for the specified sha, or nil. 
    def [](sha)
      cache[sha]
    end
    
    # Sets the cached attrs for the specified sha.
    def []=(sha, attrs)
      cache[sha] = attrs
    end
    
    # Stores a hash of attrs into the repo under a directory as specified by
    # date. The actual path will be 'YYYY/MMDD/sha' and the hash is serialized
    # as JSON.  Returns the sha of the serialized data.
    #
    # Store will cache the attrs in cache, if specified.
    def store(attrs={}, date=Time.now, store_in_cache=true)
      sha = git.set(:blob, JSON.generate(attrs))
      
      git[date_path(date, sha)] = sha.to_sym
      cache[sha] = attrs if store_in_cache
      
      sha
    end
    
    # Reads an deserializes specified hash of attrs.  If sha does not indicate
    # a blob that deserializes as JSON then read returns nil.
    def read(sha)
      begin
        JSON.parse(git.get(:blob, sha).data)
      rescue JSON::ParserError, Errno::EISDIR 
        nil
      end
    end
    
    # Creates a link file for parent and child:
    #
    #   pa/rent/child (empty_sha)
    #
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
    
    # Creates an update file for old and new shas:
    #
    #   ol/d_sha/new_sha (old_sha)
    #
    def update(old_sha, new_sha)
      if old_sha == new_sha
        raise "cannot update with self: #{old_sha} -> #{new_sha}"
      end
      
      current = linkage(old_sha, new_sha)
      if current && current == empty_sha
        raise "cannot update with a link: #{old_sha} -> #{new_sha}"
      end
      
      git[sha_path(old_sha, new_sha)] = old_sha.to_sym
      self
    end
    
    # Creates a delete file for the sha:
    #
    #   sh/a/sha (sha)
    #
    def delete(sha)
      git[sha_path(sha, sha)] = sha.to_sym
      self
    end
    
    # Returns the sha for the linkage file between the source and target.
    def linkage(source, target)
      links = git.tree.subtree(sha_path(source))
      return nil unless links
      
      mode, sha = links[target]
      sha
    end
    
    # Returns the linkage type, given the source, target and sha.
    def linkage_type(source, target, sha=linkage(source, target))
      case sha
      when empty_sha then :link
      when target    then :delete
      when source    then :update
      else :invalid
      end
    end
    
    # Yield each linkage off of source to the block, with the linkage type.
    def each_linkage(source) # :yields: target, type
      return self if source.nil?
      
      linkages = git.tree.subtree(sha_path(source))
      linkages.each_pair do |target, (mode, sha)|
        yield(target, linkage_type(source, target, sha))
      end if linkages
      
      self
    end

    # Yields the sha of each document in the repo, ordered by date (with day
    # resolution).  Each does not distinguish between indexed and non-indexed
    # documents.
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
    
    # Returns an array of shas representing recent documents added.  Paging
    # options may be specified:
    #
    #   n:: number of shas to include (default 10)
    #   offset:: offset to start timeline (default 0)
    #
    # A block may be given to filter shas.  Only shas for which the block
    # returns true will make it into the timeline.
    def timeline(options={})
      options = {:n => 10, :offset => 0}.merge(options)
      offset = options[:offset]
      n = options[:n]

      shas = []
      return shas if n <= 0

      each do |sha|
        if block_given?
          next unless yield(sha)
        end
        
        if offset > 0
          offset -= 1
        else
          shas << sha
          break if n && shas.length == n
        end
      end
      shas
    end
    
    # Initializes a Graph for the sha.
    def graph(sha)
      Graph.new(self, sha)
    end
    
    # Returns an array of revisions (commits) reachable from the sha.  These
    # revisions are cached into the index for quick retreival.
    def rev_list(sha)
      sha = resolve(sha)
      rev_lists = idx['cache']
      
      unless rev_lists.has_key?(sha)
        rev_lists[sha] = git.rev_list(sha)
      end
      
      rev_lists[sha]
    end
    
    # Returns a list of document shas that have been added ('A') between a and
    # b. Deleted ('D') or modified ('M') documents can be specified using
    # type.
    def diff(a, b, type='A')
      if a == b || b.nil?
        return []
      end
      
      paths = a.nil? ? git.ls_tree(b) : git.diff_tree(a, b)[type]
      paths.collect! do |path|
        path =~ DOCUMENT
        $3
      end

      paths.compact!
      paths
    end
    
    # Generates a status message based on currently uncommitted changes.
    def status(&block)
      block ||= lambda {|sha| sha}
      
      lines = []
      git.status.each_pair do |path, state|
        status = case path
        when DOCUMENT
          doc_status($3, self[$3], &block)
        when LINK
          mode, ref = git.tree.subtree([$1, $2])[$3]
          link_status("#{$1}#{$2}", $3, ref.to_s, &block)
        else
          ['unknown', path]
        end
        
        if status
          status.unshift state_str(state)
          lines << status
        end
      end
      
      format_status(lines).join("\n")
    end
    
    # Commits any changes to git and writes the index to disk.  The commit
    # message is inferred from the status, if left unspecified.  Commit will
    # raise an error if there are no changes to commit.
    def commit(msg=status)
      sha = git.commit(msg)
      idx.write(sha)
      sha
    end
    
    # Same as commit but does not check if there are changes to commit, useful
    # when you know there are changes to commit and don't want the overhead of
    # checking for changes.
    def commit!(msg=status)
      sha = git.commit!(msg)
      idx.write(sha)
      sha
    end
    
    # Sets self as the current Repo for the duration of the block.
    def scope
      Repo.with_env(REPO => self) { yield }
    end

    protected
    
    # Returns the sha for an empty string, and ensures the corresponding
    # object is set in the repo.
    def empty_sha # :nodoc:
      @empty_sha ||= git.set(:blob, "")
    end
  end
end