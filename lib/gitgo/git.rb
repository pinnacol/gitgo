require 'grit'
require 'gitgo/patches/grit'
require 'gitgo/git/tree'
require 'gitgo/git/utils'

module Gitgo
  
  # A wrapper to a Grit::Repo that allows access and modification of a git
  # repository without checking files out (under most circumstances).  The api
  # is patterned after the git command line interface.
  #
  # == Usage
  #
  # Checkout, add, and commit new content:
  #
  #   git = Git.init("example", :author => "John Doe <jdoe@example.com>")
  #   git.add(
  #     "README" => "New Project",
  #     "lib/project.rb" => "module Project\nend",
  #     "remove_this_file" => "won't be here long...")
  #
  #   git.commit("setup a new project")
  #
  # Content may be removed as well:
  #
  #   git.rm("remove_this_file")
  #   git.commit("removed extra file")
  #                                
  # Now access the content:
  #
  #   git["/"]                          # => ["README", "lib"]
  #   git["/lib/project.rb"]            # => "module Project\nend"
  #   git["/remove_this_file"]          # => nil
  #
  # You can go back in time if you wish:
  #
  #   git.branch = "gitgo^"
  #   git["/remove_this_file"]          # => "won't be here long..."
  #
  # For direct access to the Grit objects, use get:
  #
  #   git.get("/lib").id                # => "cad0dc0df65848aa8f3fee72ce047142ec707320"
  #   git.get("/lib/project.rb").id     # => "636e25a2c9fe1abc3f4d3f380956800d5243800e"
  #
  # === The Working Tree
  #
  # Changes to the repo are tracked by an in-memory working tree until being
  # committed. Trees can be thought of as a hash of (path, [:mode, sha]) pairs
  # representing the contents of a directory.
  #
  #   git = Git.init("example", :author => "John Doe <jdoe@example.com>")
  #   git.add(
  #     "README" => "New Project",
  #     "lib/project.rb" => "module Project\nend"
  #   ).commit("added files")
  #
  #   git.tree
  #   # => {
  #   #   "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   "lib" => {
  #   #     "project.rb" => [:"100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"]
  #   #   }
  #   # }
  #
  # Trees can be collapsed using reset.  Afterwards subtrees are only expanded
  # as needed; before expansion they appear as a [:mode, sha] pair and after
  # expansion they appear as a hash.  Symbol paths are used to differentiate
  # subtrees (which can be expanded) from blobs (which cannot be expanded).
  #
  #   git.reset
  #   git.tree
  #   # => {
  #   #   "README" => [:"100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   :lib =>     [:"040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
  #   # }
  #
  #   git.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
  #   git.tree
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
  #   git.rm("README")
  #   git.tree
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
  #   git.status
  #   # => {
  #   #   "README" => :rm
  #   #   "lib/project/utils.rb" => :add
  #   # }
  #
  class Git
    class << self
      # Creates a Git instance for path, initializing the repo if necessary.
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
      
      # Sets up Grit to log to the device for the duration of the block.
      # Primarily useful during debugging, and inadvisable otherwise because
      # the logger must be shared among all Grit::Repo instances (this is a
      # consequence of how logging is implemented in Grit).
      def debug(dev=$stdout)
        current_logger = Grit.logger
        current_debug = Grit.debug
        begin
          Grit.logger = Logger.new(dev)
          Grit.debug = true
          yield
        ensure
          Grit.logger = current_logger
          Grit.debug = current_debug
        end
      end
    end
    include Enumerable
    include Utils
    
    # The default branch
    DEFAULT_BRANCH = 'gitgo'
    
    # The default remote branch for push/pull
    DEFAULT_REMOTE_BRANCH = 'origin/gitgo'
    
    # The default directory for gitgo-related files
    DEFAULT_WORK_DIR = 'gitgo'
    
    # The default blob mode used for added content
    DEFAULT_BLOB_MODE = "100644".to_sym
    
    # The default tree mode used for added trees
    DEFAULT_TREE_MODE = "40000".to_sym
    
    # A regexp matching a valid sha sum
    SHA  = /\A[A-Fa-f\d]{40}\z/
    
    # The minimum required version of git
    GIT_VERSION = [1,6,4,2]

    # The internal Grit::Repo
    attr_reader :grit

    # The gitgo branch
    attr_reader :branch

    # The in-memory working tree tracking any adds and removes
    attr_reader :tree
    
    # Returns the sha for the branch head
    attr_reader :head
    
    attr_reader :work_dir
    
    # The path to the temporary working tree
    attr_reader :work_tree
    
    # The path to the temporary index_file
    attr_reader :index_file
    
    # Initializes a new Git bound to the repository at the specified path.
    # Raises an error if no such repository exists.  Options can specify the
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
      @work_dir = path(options[:work_dir] || DEFAULT_WORK_DIR)
      @work_tree  = options[:work_tree] || File.join(work_dir, 'tmp', object_id.to_s)
      @index_file = options[:index_file] || File.join(work_dir, 'tmp', "#{object_id}.index")
      
      self.author = options[:author] || nil
      self.checkout options[:branch] || DEFAULT_BRANCH
    end
    
    # Returns the specified path relative to the git repository (ie the .git
    # directory).  With no arguments path returns the repository path.
    def path(*segments)
      segments.collect! {|segment| segment.to_s }
      File.join(grit.path, *segments)
    end
    
    # Returns the configured author (which should be a Grit::Actor, or similar).
    # If no author is is currently set, a default author will be determined from
    # the git configurations.
    def author
      @author ||= begin
        name =  grit.config['user.name']
        email = grit.config['user.email']
        Grit::Actor.new(name, email)
      end
    end

    # Sets the author.  The input may be a Grit::Actor, an array like [author,
    # email], a git-formatted author string, or nil.
    def author=(input)
      @author = case input
      when Grit::Actor, nil then input
      when Array  then Grit::Actor.new(*input)
      when String then Grit::Actor.from_string(*input)
      else raise "could not convert to Grit::Actor: #{input.class}"
      end
    end
    
    # Returns the remote that the current branch tracks.
    def remote
      remote = grit.config["branch.#{branch}.remote"]
      merge  = grit.config["branch.#{branch}.merge"]
      
      # No configs, no tracking.
      if remote.nil? && merge.nil?
        return nil 
      end
      
      merge =~ /^refs\/heads\/(.*)$/
      "#{remote}/#{$1}"
    end
    
    # Returns a full sha for the identifier, as determined by rev_parse. All
    # valid sha string are returned immediately; there is no guarantee the sha
    # will point to an object currently in the repo.
    #
    # Returns nil the identifier cannot be resolved to an sha.
    def resolve(id)
      case id
      when SHA, nil then id
      else rev_parse(id).first
      end
    end
    
    # Returns the type of the object identified by sha; the output of:
    #
    #    % git cat-file -t sha
    #
    def type(sha)
      grit.git.cat_file({:t => true}, sha)
    end
    
    # Returns the sha for the specified reference by reading the
    # "refs/type/name" file, or nil if the reference file does not exist. The
    # standard reference types are 'heads', 'remotes', and 'tags'.
    #
    #--
    # TODO -- remove, update merge?
    def ref(type, name)
      ref_path = path("refs/#{type}/#{name}")
      
      if File.exists?(ref_path)
        File.open(ref_path) {|io| io.read(40) }
      else
        nil
      end
    end
    
    # Gets the specified object, returning an instance of the appropriate Grit
    # class.  Raises an error for unknown types.
    def get(type, id)
      case type.to_sym
      when :blob   then grit.blob(id)
      when :tree   then grit.tree(id)
      when :commit then grit.commit(id)
      when :tag
        
        object = grit.git.ruby_git.get_object_by_sha1(id)
        if object.type == :tag 
          Grit::Tag.new(object.tag, grit.commit(object.object))
        else
          nil
        end
      
      else raise "unknown type: #{type}"
      end
    end
    
    # Sets an object of the specified type into the git repository and returns
    # the object sha.
    def set(type, content)
      grit.git.put_raw_object(content, type.to_s)
    end
    
    # Gets the content for path; either the blob data or an array of content
    # names for a tree.  Returns nil if path doesn't exist.
    def [](path, committed=false)
      tree = committed ? commit_tree : @tree
      
      segments = split(path)
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

    # Sets content for path.  The content can either be:
    #
    # * a string of content
    # * a symbol sha, translated to [default_blob_mode, sha]
    # * an array like [mode, sha]
    # * a nil, to remove content
    #
    # Note that set content is immediately stored in the repo and tracked in
    # the in-memory working tree but not committed until commit is called.
    def []=(path, content=nil)
      segments = split(path)
      unless basename = segments.pop
        raise "invalid path: #{path.inspect}"
      end
      
      tree = @tree.subtree(segments, true)
      tree[basename] = convert_to_entry(content)
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
    
    #########################################################################
    # Git API
    #########################################################################
    
    # Adds a hash of (path, content) pairs (see AGET for valid content).
    def add(paths)
      paths.each_pair do |path, content|
        self[path] = content
      end

      self
    end
    
    # Removes the content at each of the specified paths
    def rm(*paths)
      paths.each {|path| self[path] = nil }
      self
    end
    
    # Commits the in-memory working tree to branch with the specified message
    # and returns the sha for the new commit.  The branch is created if it
    # doesn't already exist.  Options can specify (as symbols):
    #
    # tree::    The sha of the tree this commit points to (default the
    #           sha for tree, the in-memory working tree)
    # parents:: An array of shas representing parent commits (default the 
    #           current commit)
    # author::  A Grit::Actor, or similar representing the commit author
    #           (default author)
    # authored_date::  The authored date (default now)
    # committer::      A Grit::Actor, or similar representing the user
    #                  making the commit (default author)
    # committed_date:: The authored date (default now)
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
      
      head
    end
    
    # Resets the working tree.  Also reinitializes grit if full is specified;
    # this can be useful after operations that change configurations or the
    # cached packs (see gc).
    def reset(full=false)
      @grit = Grit::Repo.new(path, :is_bare => grit.bare) if full
      commit = grit.commits(branch, 1).first
      @head = commit ? commit.sha : nil
      @tree = commit_tree
      
      self
    end

    # Returns a hash of (path, state) pairs indicating paths that have been
    # added or removed.  States are add/rm/mod only -- renames, moves, and
    # copies are not detected.
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
    # branch will be checked out for the duration of the block into work_tree;
    # a gitgo-specific directory distinct from the user's working directory. 
    # Checkout with a block permits the execution of git commands that must be
    # performed in a working directory.
    #
    # Returns self.
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
    def merge?(treeish=remote)
      sandbox do |git, work_tree, index_file|
        remote = ref(:remotes, treeish)
        return false if remote.nil? 
        
        local = ref(:heads, branch)
        local.nil? || (local != remote && git.merge_base({}, local, remote) != remote)
      end
    end
    
    # Merges the specified reference with the current branch, fast-forwarding
    # when possible.  This method does not need to checkout the branch into a
    # working directory to perform the merge.
    def merge(treeish=remote)
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
    def pull(remote="origin")
      sandbox do |git, work_tree, index_file|
        fetch(remote)
        merge
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
    # treeish).  Raises an error if not all args can be converted into a valid
    # sha.
    #
    # Note there is no guarantee the resulting shas indicate objects in the
    # repository; not even 'git rev-parse' will do that.
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
    
    def diff_tree(a, b)
      sandbox do |git,w,i|
        output = git.run('', :diff_tree, '', {:r => true, :name_status => true}, [a, b])
        
        diff = {'A' => [], 'D' => [], 'M' => []}
        output.split("\n").each do |line|
          next unless line =~ /^(\w)\s+\d{4}\/\d{4}\/(.{40})$/
          
          array = diff[$1] or raise "unexpected diff output:\n#{output}"
          array << $2
        end

        diff
      end
    end
    
    def ls_tree(treeish)
      sandbox do |git,w,i|
        git.run('', :ls_tree, '', {:r => true, :name_only => true}, [treeish]).split("\n")
      end
    end
    
    # Options:
    #
    #   :ignore_case
    #   :invert_match
    #   :fixed_strings
    #   :e
    #
    def grep(pattern, treeish=grit.head.commit)
      options = pattern.respond_to?(:merge) ? pattern.dup : {:e => pattern}
      options.delete_if {|key, value| nil_or_empty?(value) }
      options = options.merge!(
        :cached => true,
        :name_only => true,
        :full_name => true
      )
      
      unless commit = grit.commit(treeish)
        raise "unknown commit: #{treeish}"
      end
      
      sandbox do |git, work_tree, index_file|
        git.read_tree({:index_output => index_file}, commit.id)
        git.grep(options).split("\n").each do |path|
          yield(path, (commit.tree / path))
        end
      end
      self
    end
    
    def tree_grep(pattern, treeish=grit.head.commit)
      options = pattern.respond_to?(:merge) ? pattern.dup : {:e => pattern}
      options.delete_if {|key, value| nil_or_empty?(value) }
      
      unless commit = grit.commit(treeish)
        raise "unknown commit: #{treeish}"
      end
      
      sandbox do |git, work_tree, index_file|
        postfix = options.empty? ? '' : begin
          grep_options = git.transform_options(options)
          " | grep #{grep_options.join(' ')}"
        end
        
        stdout, stderr = git.sh("#{Grit::Git.git_binary} ls-tree -r --name-only #{git.e(commit.id)} #{postfix}")
        stdout.split("\n").each do |path|
          yield(path, commit.tree / path)
        end
      end
      self
    end
    
    def commit_grep(pattern, treeish=grit.head.commit)
      options = pattern.respond_to?(:merge) ? pattern.dup : {:grep => pattern}
      options.delete_if {|key, value| nil_or_empty?(value) }
      options[:format] = "%H"
      
      sandbox do |git, work_tree, index_file|
        git.log(options, treeish).split("\n").each do |sha|
          yield grit.commit(sha)
        end
      end
      self
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
      reset(true)
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
        return yield(grit.git, work_tree, index_file)
      end
      
      FileUtils.rm_r(work_tree) if File.exists?(work_tree)
      FileUtils.rm(index_file)  if File.exists?(index_file)
      
      begin
        FileUtils.mkdir_p(work_tree)
        @sandbox = true
        
        with_env(
          'GIT_DIR' => grit.path, 
          'GIT_WORK_TREE' => work_tree,
          'GIT_INDEX_FILE' => index_file
        ) do
          
          yield(grit.git, work_tree, index_file)
        end
      ensure
        FileUtils.rm_r(work_tree) if File.exists?(work_tree)
        FileUtils.rm(index_file)  if File.exists?(index_file)
        @sandbox = false
      end
    end
    
    protected
    
    def convert_to_entry(content) # :nodoc:
      case content
      when String then [DEFAULT_BLOB_MODE, set(:blob, content)]
      when Symbol then [DEFAULT_BLOB_MODE, content]
      when Array, nil then content
      else raise "invalid content: #{content.inspect}"
      end
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