require 'grit'
require 'gitgo/document'
require 'gitgo/patches/grit'
require 'gitgo/repo/tree'
require 'gitgo/repo/utils'
require 'gitgo/index'

module Gitgo
  
  # A wrapper to a Grit::Repo that allows access and modification of a git
  # repository without checking the repository out.  The api is patterned
  # after commands you'd invoke on the command line, although there are
  # numerous Gitgo-specific methods for working with Gitgo documents.
  #
  # == Usage
  #
  # Checkout, add, and commit new content:
  #
  #   repo = Repo.init("example", :author => "John Doe <jdoe@example.com>")
  #   repo.add(
  #     "README" => "New Project",
  #     "lib/project.rb" => "module Project\nend",
  #     "remove_this_file" => "won't be here long...")
  #
  #   repo.commit("setup a new project")
  #
  # Content may be removed as well:
  #
  #   repo.rm("remove_this_file")
  #   repo.commit("removed extra file")
  #                          
  # Now access the content:
  #
  #   repo["/"]                          # => ["README", "lib"]
  #   repo["/lib/project.rb"]            # => "module Project\nend"
  #   repo["/remove_this_file"]          # => nil
  #
  # You can go back in time if you wish:
  #
  #   repo.branch = "gitgo^"
  #   repo["/remove_this_file"]          # => "won't be here long..."
  #
  # For access to the Grit objects, use get:
  #
  #   repo.get("/lib").id                # => "cad0dc0df65848aa8f3fee72ce047142ec707320"
  #   repo.get("/lib/project.rb").id     # => "636e25a2c9fe1abc3f4d3f380956800d5243800e"
  #
  # === The Working Tree
  #
  # Changes to the repo are tracked by a Tree until being committed. Trees can
  # be thought of as a hash of (path, [:mode, sha]) pairs representing the
  # in-memory working tree contents. 
  #
  #   repo = Repo.init("example", :author => "John Doe <jdoe@example.com>")
  #   repo.add(
  #     "README" => "New Project",
  #     "lib/project.rb" => "module Project\nend"
  #   ).commit("added files")
  #
  #   repo.tree
  #   # => {
  #   #   "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   "lib" => {
  #   #     "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"]
  #   #   }
  #   # }
  #
  # Trees can be collapsed using reset.  Afterwards subtrees are only expanded
  # as needed; before expansion they appear as a [:mode, sha] pair and after
  # expansion they appear as a hash.  Symbol paths indicate a subtree that
  # could be expanded.
  #
  #   repo.reset
  #   repo.tree
  #   # => {
  #   #   "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   :lib =>     [:"040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
  #   # }
  #
  #   repo.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
  #   repo.tree
  #   # => {
  #   #   "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   "lib" => {
  #   #     "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
  #   #     "project" => {
  #   #       "utils.rb" => [:"100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"]
  #   #     }
  #   #   }
  #   # }
  #
  #   repo.rm("README")
  #   repo.tree
  #   # => {
  #   #   "lib" => {
  #   #     "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
  #   #     "project" => {
  #   #       "utils.rb" => [:"100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4"]
  #   #     }
  #   #   }
  #   # }
  #
  # The working tree can be compared with the commit tree to produce a list of
  # files that have been added and removed using the status method:
  #
  #   repo.status
  #   # => {
  #   #   "README" => :rm
  #   #   "lib/project/utils.rb" => :add
  #   # }
  #
  class Repo
    class << self
      # Initializes a Git adapter for path, creating the repo if necessary.
      def init(path=Dir.pwd, options={})
        unless File.exists?(path)
          FileUtils.mkdir_p(path)
          
          Dir.chdir(path) do
            bare = options[:is_bare] ? true : false
            gitdir = bare || path =~ /\.git$/ ? path : File.join(path, ".git")
            
            Utils.with_env('GIT_DIR' => gitdir) do
              git = Grit::Git.new(gitdir)
              git.init({:bare => bare})
            end
          end
        end
        
        new(path, options)
      end
      
      # Sets up Grit to log to the logger for the duration of the block.
      #
      # ==== Usage
      #
      # The gitlog method is set on Repo because it has global implications;
      # calls to gitlog that use different loggers will cause a error (this
      # lousy behavior is a consequence of how logging is implemented in
      # Grit). As such it should not be used except when debugging.
      def gitlog(logger=Grit.logger)
        if @@gitlog
          if Grit.logger == logger
            return yield
          else
            raise "already git logging using a different logger"
          end
        end
          
        current_logger = Grit.logger
        current_debug = Grit.debug
        begin
          @@gitlog = true
          Grit.logger = logger
          Grit.debug = true

          yield
        ensure
          Grit.logger = current_logger
          Grit.debug = current_debug
          @@gitlog = false
        end
      end
      @@gitlog = false
      
    end
    include Enumerable
    include Utils
    
    # The default branch for storing Gitgo objects.
    DEFAULT_BRANCH = 'gitgo'
    DEFAULT_BLOB_MODE = "100644".to_sym
    DEFAULT_TREE_MODE = "40000".to_sym
    DEFAULT_DIR = 'gitgo'
    DEFAULT_TRACK_BRANCH = 'origin/gitgo'
    
    YEAR = /\A\d{4,}\z/
    MMDD = /\A\d{4}\z/
    SHA  = /\A[A-Fa-f\d]{40}\z/
    
    GIT_VERSION = [1,6,4,2]

    # The internal Grit::Repo
    attr_reader :grit

    # The gitgo branch
    attr_reader :branch

    # The in-memory working tree tracking any adds and removes
    attr_reader :tree
    
    # The repo directory, where repo-specific files are stored
    attr_reader :dir
    
    # An Index to access the branch-specific index files
    attr_reader :index
    
    # Returns the head commit for the branch
    attr_reader :head
    
    # Initializes a new Git for the repo at the specified path.
    # Raises an error if no such repo exists.  Options can specify the
    # following:
    #
    #   :branch     the branch for self
    #   :author     the author for self
    #   + any Grit::Repo options
    #
    def initialize(path=Dir.pwd, options={})
      @grit = path.kind_of?(Grit::Repo) ? path : Grit::Repo.new(path, options)
      @sandbox = false
      @branch = nil
      @dir = options[:dir] || DEFAULT_DIR
      @work_tree  = path(dir, 'sandbox', object_id).freeze
      @work_index = path(dir, 'sandbox', "#{object_id}.index").freeze
      
      self.author = options[:author] || nil
      self.checkout options[:branch] || DEFAULT_BRANCH
    end
    
    # Returns the specified path relative to the git repo (ie the .git
    # directory as indicated by grit.path).  With no arguments path returns
    # the git repo path.
    def path(*segments)
      segments.collect! {|segment| segment.to_s }
      File.join(grit.path, *segments)
    end
    
    # Returns the configured author (which should be a Grit::Actor, or similar).
    # If no author is is currently set, a default author will be determined from
    # the repo configurations.
    def author
      @author ||= begin
        name =  grit.config['user.name']
        email = grit.config['user.email']
        Grit::Actor.new(name, email)
      end
    end

    # Sets the author.  The input may be a Grit::Actor, an array like [author,
    # email], a git-formatted author string (ex 'John Doe <jdoe@example.com>'),
    # or nil.
    def author=(input)
      @author = case input
      when Grit::Actor, nil then input
      when Array  then Grit::Actor.new(*input)
      when String then Grit::Actor.from_string(*input)
      else raise "could not convert to Grit::Actor: #{input.class}"
      end
    end
    
    # Returns the remote that the current branch tracks.
    def track
      remote = grit.config["branch.#{branch}.remote"]
      merge  = grit.config["branch.#{branch}.merge"]
      
      # No configs, no tracking.
      if remote.nil? && merge.nil?
        return nil 
      end
      
      merge =~ /^refs\/heads\/(.*)$/
      "#{remote}/#{$1}"
    end
    
    # Returns the git version as an array of integers like [1,6,4,2]. The
    # version array is intended to be compared with other versions in this
    # way:
    #
    #   def version_ok?(required, actual)
    #     (required <=> actual) <= 0
    #   end
    #
    #   version_ok?([1,6,4,2], [1,6,4,2])     # => true
    #   version_ok?([1,6,4,2], [1,6,4,3])     # => true
    #   version_ok?([1,6,4,2], [1,6,4,1])    # => false
    #
    def version
      grit.git.version.split(/\s/).last.split(".").collect {|i| i.to_i}
    end
    
    # Checks if the git version is compatible with GIT_VERSION.  This check is
    # performed once and then cached.
    def version_ok?
      @version_ok ||= ((GIT_VERSION <=> version) <= 0)
    end
    
    # Returns the type of the object identified by sha; the output of:
    #
    #    % git cat-file -t sha
    #
    def type(sha)
      grit.git.cat_file({:t => true}, sha)
    end
    
    # Gets the specified object, returning an instance of the appropriate Grit
    # class.  Raises an error for unknown types.
    def get(type, id)
      case type.to_sym
      when :blob          then grit.blob(id)
      when :tree          then grit.tree(id)
      when :commit, :tag  then grit.commit(id)
      else raise "unknown type: #{type}"
      end
    end
    
    # Sets an object into the git repository and returns the object id.
    def set(type, content)
      grit.git.put_raw_object(content, type.to_s)
    end
    
    # Returns the sha for the specified reference by reading the
    # "refs/type/name" file, or nil if the reference file does not exist. The
    # standard reference types are 'heads', 'remotes', and 'tags'.
    def ref(type, name)
      ref_path = path("refs/#{type}/#{name}")
      
      if File.exists?(ref_path)
        File.open(ref_path) {|io| io.read(40) }
      else
        nil
      end
    end
    
    # Gets the content for path; either the blob data or an array of content
    # names for a tree.  Returns nil if path doesn't exist.
    def [](path, committed=false)
      tree = committed ? commit_tree : @tree
      
      segments = path_segments(path)
      unless basename = segments.pop
        return tree.keys
      end
      
      unless tree = tree.subtree(segments)
        return nil 
      end
      
      obj = tree[basename]
      case obj
      when Array then get(:blob, obj[1]).data
      when Tree  then obj.keys
      else nil
      end
    end

    # Sets content for path. 
    def []=(path, content=nil)
      add(path => content)
    end
    
    #########################################################################
    # Git API
    #########################################################################
    
    # Adds content at the specified paths.  Takes a hash of (path, content)
    # pairs where the content can either be:
    #
    # * a string of content
    # * an array like [mode, sha] (for blobs)
    # * a hash of (path, [mode, sha]) pairs (for trees)
    # * a nil, to remove content
    #
    # If update is true, then string contents will be updated with a
    # [mode, sha] array representing the new blob.
    def add(paths, update=false)
      paths.keys.each do |path|
        segments = path_segments(path)
        unless basename = segments.pop
          raise "invalid path: #{path.inspect}"
        end
        
        entry = paths[path]
        entry = [DEFAULT_BLOB_MODE, set(:blob, entry)] if entry.kind_of?(String)
        
        tree = @tree.subtree(segments, true)
        
        paths[path] = entry.nil? ? tree[basename] : entry if update
        tree[basename] = entry
      end

      self
    end
    
    # Removes the content at each of the specified paths
    def rm(*paths)
      nils = {}
      paths.each {|path| nils[path] = nil }
      add(nils)
      self
    end
    
    # Commits the current tree to branch with the specified message and
    # returns the sha for the new commit.  The branch is created if it doesn't
    # already exist.  Options can specify (as symbols):
    #
    #   tree::    The sha of the tree this commit points to (default the
    #             sha for tree, the in-memory working tree)
    #   parents:: An array of shas representing parent commits (default the 
    #             current commit)
    #   author::  A Grit::Actor, or similar representing the commit author
    #             (default author)
    #   authored_date::  The authored date (default now)
    #   committer::      A Grit::Actor, or similar representing the user
    #                    making the commit (default author)
    #   committed_date:: The authored date (default now)
    #
    # Raises an error if there are no changes to commit.
    def commit(message, options={})
      raise "no changes to commit" if status.empty?
      commit!(message, options)
    end
    
    # Same as commit but does not check if there are changes to commit, useful
    # when you know there are changes to commit and don't want unnecessary
    # overhead.
    def commit!(message, options={})
      now = Time.now
      
      tree_id = options.delete(:tree) || write_tree(tree)[1]
      parents = options.delete(:parents) || (head ? [head] : [])
      author = options[:author] || self.author
      authored_date = options[:authored_date] || now
      committer = options[:committer] || author
      committed_date = options[:committed_date] || now

      # commit format:
      #---------------------------------------------------
      #   tree sha
      #   parent sha
      #   author name <email> time_as_int zone_offset
      #   committer name <email> time_as_int zone_offset
      #   
      #   messsage
      #   
      #---------------------------------------------------
      # Note there is a trailing newline after the message.
      #
      lines = []
      lines << "tree #{tree_id}"
      parents.each do |parent|
        lines << "parent #{parent}"
      end
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
      lines << ""
      
      @head = set('commit', lines.join("\n"))
      grit.update_ref(branch, head)
      index.write(head)
      
      head
    end
    
    # Resets the working tree.
    #
    # Options (specify using symbols):
    #
    #   full:: When specified, grit will also be reinitialized; this can be
    #          useful because grit caches information like configs and packs.
    #
    def reset(options={})
      @grit = Grit::Repo.new(path, :is_bare => grit.bare) if options[:full]
      commit = grit.commits(branch, 1).first
      @head = commit ? commit.sha : nil
      @tree = commit_tree
      
      # reset the index
      @index = Index.new(path(dir, 'index', branch))
      reindex if reindex?
      
      self
    end

    # Returns a hash of (path, state) pairs indicating paths that have been
    # added or removed.  State must be :add or :rm.
    def status(full=false)
      a = commit_tree.flatten
      b = tree.flatten
      
      diff = {}
      (a.keys | b.keys).collect do |key|
        a_entry = a.has_key?(key) ? a[key] : nil
        b_entry = b.has_key?(key) ? b[key] : nil
        
        change = case
        when a_entry && b_entry
          next unless a_entry != b_entry
          :mod
        when a_entry
          :rm
        when b_entry
          :add
        end
        
        diff[key] = full ? [change, a_entry || [], b_entry || []] : change
      end
      diff
    end

    # Sets the current branch and updates tree.  Checkout does not actually
    # checkout any files unless a block is given.  In that case, the current
    # branch will be checked out for the duration of the block into a
    # gitgo-specific directory that is distinct from the user's working
    # directory.  Checkout with a block permits the execution of git commands
    # that must be performed in a working directory.
    #
    # Returns self.
    #
    # ==== Technical Notes
    #
    # Checkout requires the use of an independent work tree and index file so
    # as not to conflict with the user's working directory.  These are given
    # by:
    #
    #   work_tree  = repo.path(Repo::WORK_TREE)
    #   index_file = repo.path(Repo::INDEX_FILE)
    #
    # Both are located within the .git directory, under the 'gitgo' directory.
    def checkout(branch=self.branch) # :yields: working_dir
      if branch != @branch
        @branch = branch
        reset
      end
      
      if block_given?
        sandbox do |git, work_tree, index_file|
          git.read_tree({:index_output => index_file}, branch)
          git.checkout_index({:a => true})
          yield(work_tree)
        end
      end
      
      self
    end
    
    # Fetches from the remote.
    def fetch(remote="origin")
      sandbox {|git,w,i| git.fetch({}, remote) }
      self
    end
    
    # Returns true if a merge update is available for branch.
    def merge?(remote=track)
      sandbox do |git, work_tree, index_file|
        remote = ref(:remotes, remote)
        return false if remote.nil? 
        
        local = ref(:heads, branch)
        local.nil? || (local != remote && git.merge_base({}, local, remote) != remote)
      end
    end
    
    # Merges the specified reference with the current branch, fast-forwarding
    # when possible.  This method does not need to checkout the branch into a
    # working directory to perform the merge.
    def merge(treeish=track)
      sandbox do |git, work_tree, index_file|
        local, remote = rev_parse(branch, treeish)
        base = local.nil? ? nil : git.merge_base({}, local, remote).chomp("\n")
        
        case
        when base == remote
          break
        when base == local
          # fast forward situation
          grit.update_ref(branch, remote)
        else
          # todo: add rebase as an option
          
          git.read_tree({
            :m => true,          # merge
            :i => true,          # without a working tree
            :trivial => true,    # only merge if no file-level merges are required
            :aggressive => true, # allow resolution of removes
            :index_output => index_file
          }, base, branch, remote)
          
          commit!("gitgo merge of #{treeish} into #{branch}", 
            :tree => git.write_tree.chomp("\n"),
            :parents => [local, remote]
          )
        end
        
        reset
      end
      
      self
    end
    
    # Push changes to the remote.
    def push(remote="origin")
      sandbox do |git, work_tree, index_file|
        git.push({}, remote, branch)
      end
    end
    
    # Pulls from the remote into the work tree.
    def pull(remote="origin", ref=track)
      sandbox do |git, work_tree, index_file|
        fetch(remote)
        merge(ref)
      end
      reset
    end

    # Clones self into the specified path and sets up tracking of branch in
    # the new grit.  Clone was primarily implemented for testing; normally
    # clones are managed by the user.
    def clone(path, options={})
      with_env do
        grit.git.clone(options, grit.path, path)
        clone = Grit::Repo.new(path)

        if options[:bare]
          # bare origins directly copy branch heads without mapping them to
          # 'refs/remotes/origin/' (see git-clone docs). this maps the branch
          # head so the bare grit can checkout branch
          clone.git.remote({}, "add", "origin", grit.path)
          clone.git.fetch({}, "origin")
          clone.git.branch({}, "-D", branch)
        end

        # sets up branch to track the origin to enable pulls
        clone.git.branch({:track => true}, branch, "origin/#{branch}")
        self.class.new(clone, :branch => branch, :author => author)
      end
    end
    
    # Returns an array of shas identified by the args (ex a sha, short-sha, or
    # treeish).  Raises an error if not all args can be converted into something
    # that looks like a sha.
    #
    # Note there is no guarantee the rev-parse will return a sha to a valid
    # object --- not even 'git rev-parse' will do that.
    def rev_parse(*args)
      return args if args.empty?
      
      sandbox do |git,w,i|
        shas = git.run('', :rev_parse, '', {}, args).split("\n")
        
        # Grit::Git#run only makes stdout available, not stderr, and so this
        # wonky check relies on the fact that git rev-parse will print the
        # unresolved ref to stdout and quit if it can't succeed. That means
        # the last printout will not look like a sha in the event of an error.
        
        unless shas.last.to_s =~ SHA
          raise "could not resolve to a sha: #{args.last}"
        end
        
        shas
      end
    end
    
    # Returns an array of revisions (commits) reachable from the treeish.
    def rev_list(*treeishs)
      return treeishs if treeishs.empty?
      sandbox {|git,w,i| git.run('', :rev_list, '', {}, treeishs).split("\n") }
    end
    
    # Peforms 'git prune' and returns self.
    def prune
      sandbox {|git,w,i| git.prune }
      self
    end
    
    # Performs 'git gc' and resets self so that grit will use the updated pack
    # files.  Returns self.
    def gc
      sandbox {|git,w,i| git.gc }
      
      # reinitialization is required at this point because grit packs; once
      # you gc the packs change and Grit::GitRuby bombs.
      reset(:full => true)
    end
    
    # Performs 'git fsck' and returns the output.
    def fsck
      sandbox do |git, work_tree, index_file|
        stdout, stderr = git.sh("#{Grit::Git.git_binary} fsck")
        "#{stdout}#{stderr}"
      end
    end
    
    # Returns a hash of repo statistics parsed from 'git count-objects
    # --verbose'.
    def stats
      sandbox do |git, work_tree, index_file|
        stdout, stderr = git.sh("#{Grit::Git.git_binary} count-objects --verbose")
        stats = YAML.load(stdout)
        
        unless stats.kind_of?(Hash)
          raise stderr
        end
        
        stats
      end
    end
    
    def sandbox
      if @sandbox
        return yield(grit.git, @work_tree, @work_index)
      end
      
      FileUtils.rm_r(@work_tree) if File.exists?(@work_tree)
      FileUtils.rm(@work_index)  if File.exists?(@work_index)
      
      begin
        FileUtils.mkdir_p(@work_tree)
        @sandbox = true
        
        with_env(
          'GIT_DIR' => grit.path, 
          'GIT_WORK_TREE' => @work_tree,
          'GIT_INDEX_FILE' => @work_index
        ) do
          
          yield(grit.git, @work_tree, @work_index)
        end
      ensure
        FileUtils.rm_r(@work_tree) if File.exists?(@work_tree)
        FileUtils.rm(@work_index)  if File.exists?(@work_index)
        @sandbox = false
      end
    end
    
    #########################################################################
    # Document API
    #########################################################################

    # Creates a new Document using the content and attributes, writes it to
    # the repo and returns it's sha.  New documents are stored by timestamp.
    def create(content, attrs={}, options={})
      attrs['author'] ||= author
      attrs['date']   ||= Time.now

      store(Document.new(attrs, content), options)
    end

    # Stores the document by timestamp.
    def store(doc, options={})
      mode = options[:mode] || DEFAULT_BLOB_MODE
      id = set(:blob, doc.to_s)

      add(timestamp(doc.date, id) => [mode, id])
      index.add(doc, id)
      
      id
    end

    # Gets the document indicated by id, or nil if no such document exists, or
    # if the id points to something other than a document.
    def read(id)
      begin
        Document.parse(grit.blob(id).data, id)
      rescue Document::InvalidDocumentError, Errno::EISDIR
        nil
      end
    end
    
    # Updates the specified document with the document, reassigning all links.
    def update(id, doc)
      return nil unless old_doc = read(id)

      parents = self.parents(id)
      children = self.children(id)
      
      parents.each {|parent| unlink(parent, id) }
      children.each {|child| unlink(id, child) }
      
      index.rm(old_doc)
      rm timestamp(old_doc.date, id)

      id = store(doc)
      parents.each {|parent| link(parent, id) }
      children.each {|child| link(id, child) }

      doc.sha = id
      doc
    end

    # Removes the document from the repo by deleting it from the timeline.
    def destroy(id, unlink=true)

      # Destroying a doc with children is a bad idea because there is no one
      # good way of removing the children.  Children with multiple parents
      # should not be unlinked recursively.  Children with no other parents
      # should be unlinked and destroyed (because nothing will reference them
      # anymore).
      #
      # Note the same is not true for parents; a doc can simply remove itself
      # from the parents, each of which will remain valid afterwards.
      if unlink && !children(id).empty?
        raise "cannot destroy a document with children"
      end

      return nil unless doc = read(id)
      
      if unlink
        parents(id).each {|parent| unlink(parent, id) }
      end
      
      index.rm(doc)
      rm timestamp(doc.date, id)
      
      doc
    end
    
    # A self-filling cache of documents that only reads a document once.  The
    # cache is intended to be set to a variable and re-used like this:
    #
    #   repo = Repo.init("path/to/git_dir")
    #   id = repo.create("new doc")
    #
    #   docs = repo.cache
    #   docs[id].content           # => "new doc"
    #   docs[id].equal?(docs[id])  # => true
    #
    # Call cache again to generate a new cache:
    #
    #   alts = repo.cache
    #   alts[id].content           # => "new doc"
    #   alts[id].equal?(docs[id])  # => false
    #
    def cache
      Hash.new {|hash, id| hash[id] = read(id) }
    end
    
    # Yields the sha of each document in the repo, ordered by date (with day
    # resolution), regardless of whether they are indexed or not.
    def each
      years = self[[]] || []
      years.sort!
      years.reverse_each do |year|
        next unless year =~ YEAR
        
        mmdd = self[[year]] || []
        mmdd.sort!
        mmdd.reverse_each do |mmdd|
          next unless mmdd =~ MMDD
          
          # y,md need to be iterated in reverse to correctly sort by
          # date; this is not the case with the unordered shas
          self[[year, mmdd]].each do |sha|
            yield(sha)
          end
        end
      end
    end
    
    # Returns an array of shas representing recent documents added.
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
    
    def changes(a, b=nil)
      a, b = "#{a}^", a if b.nil?
      output = sandbox {|git,w,i| git.diff_tree({:r => true, :name_status => true}, a, b) }
      
      adds = []
      removes = []
      output.split("\n").each do |line|
        next unless line =~ /^(\w)\s+\d{4}\/\d{4}\/(.{40})$/
        
        case $1
        when 'A' then adds << $2
        when 'D' then removes << $2
        else raise "unexpected diff output:\n#{output}"
        end
      end
      
      [adds, removes]
    end
    
    # Links the parent and child by adding a reference to the child under the
    # sha path for the parent.
    #
    # While parent can refer to any git object, only blobs and trees should be
    # linked as children; other object types (ex commit, tag) are seen as
    # corruption by git. 
    #  
    def link(parent, child, options={})
      ref = options[:ref]
      sha = ref ? set(:blob, ref) : empty_sha
      
      add(sha_path(options, parent, child) => [DEFAULT_BLOB_MODE, sha])
      
      self
    end

    # Returns an array of parents that link to the child.  Note this is a very
    # expensive operation because it fully expands the in-memory working tree.
    def parents(child, options={})
      segments = path_segments(options[:dir] || "/")
      parents = []
      
      # seek /ab/xyz/sha where sha == child
      @tree.subtree(segments).each_tree(true) do |ab, ab_tree|
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

    # Returns an array of children linked to the parent.  If recursive is
    # specified, this method will recursively seek children for each child and
    # the return will be a nested hash of linked shas.
    def children(parent, options={})
      children = self[sha_path(options, parent)] || []

      return children unless options[:recursive]

      tree = options[:tree] ||= {}
      tree[parent] = children

      visited = options[:visited] ||= [parent]
      children.each do |child|
        circular = visited.include?(child)
        visited.push child

        if circular
          raise "circular link detected:\n  #{visited.join("\n  ")}\n"
        end
        
        unless tree.has_key?(child)
          children(child, options)
        end
        
        visited.pop
      end

      tree
    end
    
    # Returns the sha of the object the linked child refers to, ie the :ref
    # option used when making a link. 
    def reference(parent, child, options={})
      self[sha_path(options, parent, child)]
    end

    # Unlinks the parent and child by removing the reference to the child
    # under the sha-path for the parent.  Unlink will recursively remove all
    # links to the child if specified.
    def unlink(parent, child, options={})
      return self unless parent && child
      rm(sha_path(options, parent, child))

      if options[:recursive]
        visited = options[:visited] ||= []

        # the child should only need to be visited once
        # as one visit will unlink any grandchildren
        unless visited.include?(child)
          visited.push child

          # note options cannot be passed to links here,
          # because recursion is NOT desired and visited
          # will overlap/conflict
          children(child, :dir => options[:dir]).each do |grandchild|
            unlink(child, grandchild, options)
          end
        end
      end

      self
    end
    
    def tails(sha)
      tails = []
      children(sha, :recursive => true).each_pair do |key, value|
        tails << key if value.empty?
      end
      tails
    end
    
    # Returns a list of all documents that are descendants of the specified
    # document. The return is specially formatted for conversion into nested
    # lists (see below).
    #
    # Comments takes a document cache as a second argument, to prevent a
    # single document from being read multiple times.  During this method
    # tail documents are flagged using the :tail attribute.
    #
    # ==== Implementation and Usage
    #
    # Comments uses the flatten and collapse methods (see Gitgo::Repo::Utils)
    # to collect comments into a flattened, list-friendly ancestry that only
    # represents existing, rather than potential, branch points.  For example,
    # given this parent-child hierarchy:
    #
    #   a
    #   `- b
    #      |- c
    #      `- d
    #         ` e
    #
    # The results are structured to render this:
    #
    #   a
    #   b
    #   |- c
    #   `- d
    #      e
    #
    # More specifically:
    #
    #   ancestry = {
    #     "a" => ["b"],
    #     "b" => ["c", "d"],
    #     "c" => [],
    #     "d" => ["e"],
    #     "e" => []
    #   }
    #
    #   ancestry_for_a = flatten(ancestry)['a']
    #   comments = collapse(ancestry_for_a)
    #   comments # => ["a", "b", ["c"], ["d", "e"]]
    #
    # To generate the flattened list, recursively iterate over the results of
    # comments and add a list item for each non-array and a nested list for
    # each array.  For example:
    #
    #   def render(comments, lines=[], indent="")
    #     lines << "#{indent}<ul>"
    #
    #     comments.each do |comment|
    #       if comment.kind_of?(Array)
    #         lines << "#{indent}<li>"
    #         render(comment, lines, indent + "  ")
    #         lines << "#{indent}</li>"
    #       else
    #         lines << "#{indent}<li>#{comment}</li>"
    #       end
    #     end
    #
    #     lines << "#{indent}</ul>"
    #     lines
    #   end
    #
    #   "\n" + render(comments).join("\n") + "\n"
    #   # => %q{
    #   # <ul>
    #   # <li>a</li>
    #   # <li>b</li>
    #   # <li>
    #   #   <ul>
    #   #   <li>c</li>
    #   #   </ul>
    #   # </li>
    #   # <li>
    #   #   <ul>
    #   #   <li>d</li>
    #   #   <li>e</li>
    #   #   </ul>
    #   # </li>
    #   # </ul>
    #   # }
    #
    #--
    # Note the documenation test for the imp/usage is in utils_test.rb
    def comments(sha, docs=cache)
      ancestry = {}
      children(sha, :recursive => true).each_pair do |parent, children|
        next if parent == sha
        
        doc = docs[parent]
        doc[:tail] ||= children.empty?
        
      end.each_pair do |parent, children|
        parent = docs[parent] unless parent == sha
        
        children.collect! {|id| docs[id] }.sort_by {|doc| doc.date }.reverse!
        ancestry[parent] = children
      end
    
      comments = flatten(ancestry)[sha]
      comments = collapse(comments)
      comments.shift
      
      comments
    end
    
    # Determines whether the repo needs reindexing.  Returns false if the
    # repo head is the same as or behind the index head.
    def reindex?
      return false if head.nil?
      
      index_head = index.head
      index_head.nil? || head != index_head && !rev_list(index_head).include?(head)
    end
    
    # Reindexes documents in the repo.
    def reindex
      return self unless head
      
      if index.head
        adds, removes = changes(head, index.head)
        adds.each {|sha| index.add read(sha) }
        removes.each {|sha| index.rm read(sha) }
      else
        each {|sha| index.add read(sha) }
      end
      
      index.write(head)
      self
    end
    
    protected
    
    # Creates a nested sha path like:
    #
    #   dir/
    #     ab/
    #       xyz...
    #
    # By default dir is "/" but options can be used to specify an alternative.
    def sha_path(options, sha, *paths) # :nodoc:
      paths.unshift sha[2,38]
      paths.unshift sha[0,2]
      
      if dir = options[:dir]
        paths = File.join(dir, *paths)
      end
      
      paths
    end
    
    def timestamp(date, id) # :nodoc:
      date.strftime("%Y/%m%d/#{id}")
    end
    
    # Returns the sha for an empty file.  Note this only needs to be
    # initialized once for a given repo; even if you change branches the
    # object will be in the repo.
    def empty_sha # :nodoc:
      @empty_sha ||= set(:blob, "")
    end
    
    def commit_tree # :nodoc:
      tree = head ? get(:commit, head).tree : nil
      Tree.new(tree)
    end
    
    # tree format:
    #---------------------------------------------------
    #   mode name\0[packedsha]mode name\0[packedsha]...
    #---------------------------------------------------
    # note there are no newlines separating tree entries.
    def write_tree(tree) # :nodoc:
      tree_mode = tree.mode ||= DEFAULT_TREE_MODE
      tree_id   = tree.sha  ||= begin
        lines = []
        tree.each_pair(false) do |key, entry|
          mode, id = case entry
          when Tree  then write_tree(entry)
          when Array then entry
          else [entry.mode, entry.id]
          end
          
          line = "#{mode} #{key}\0#{[id].pack("H*")}"
          
          # modes should not begin with zeros (although it is not fatal
          # if they do), otherwise fsck will print warnings like this:
          #
          # warning in tree 980127...: contains zero-padded file modes
          if line =~ /\A0+(.*)\z/
            line = $1
          end
          
          lines << line
        end
        
        set(:tree, lines.join)
      end
      
      [tree_mode, tree_id]
    end
  end
end