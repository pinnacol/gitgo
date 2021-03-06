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
  # == Tracking, Push/Pull
  #
  # Git provides limited support for setting a tracking branch and doing
  # push/pull from tracking branches without checking the gitgo branch out.
  # More complicated operations can are left to the command line, where the
  # current branch can be directly manipulated by the git program.
  #
  # Unlike git (the program), Git (the class) requires the upstream branch
  # setup by 'git branch --track' to be an existing tracking branch.  As an
  # example, if you were to setup this:
  #
  #   % git branch --track remote/branch
  #
  # Or equivalently this:
  #
  #   git = Git.init
  #   git.track "remote/branch"
  #
  # Then Git would assume: 
  #
  # * the upstream branch is 'remote/branch'
  # * the tracking branch is 'remotes/remote/branch'
  # * the 'branch.name.remote' config is 'remote'
  # * the 'branch.name.merge' config is 'refs/heads/branch'
  #                        
  # If ever these assumptions are broken, for instance if the gitgo branch is
  # manually set up to track a local branch, methods like pull/push could
  # cause odd failures.  To help check:
  #         
  # * track will raise an error if the upstream branch is not a tracking
  #   branch
  # * upstream_branch raises an error if the 'branch.name.merge' config
  #   doesn't follow the 'ref/heads/branch' pattern
  # * pull/push raise an error given a non-tracking branch
  #
  # Under normal circumstances, all these assumptions will be met.
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
      
      # Returns the git version as an array of integers like [1,6,4,2]. The
      # version query performed once and then cached.
      def version
        @version ||= `git --version`.split(/\s/).last.split(".").collect {|i| i.to_i}
      end

      # Checks if the git version is compatible with GIT_VERSION.  This check is
      # performed once and then cached.
      def version_ok?
        @version_ok ||= ((GIT_VERSION <=> version) <= 0)
      end
    end
    
    include Enumerable
    include Utils
    
    # The default branch
    DEFAULT_BRANCH = 'gitgo'
    
    # The default upstream branch for push/pull
    DEFAULT_UPSTREAM_BRANCH = 'origin/gitgo'
    
    # The default directory for gitgo-related files
    DEFAULT_WORK_DIR = 'gitgo'
    
    # The default blob mode used for added blobs
    DEFAULT_BLOB_MODE = '100644'.to_sym
    
    # The default tree mode used for added trees
    DEFAULT_TREE_MODE = '40000'.to_sym
    
    # A regexp matching a valid sha sum
    SHA  = /\A[A-Fa-f\d]{40}\z/
    
    # The minimum required version of git (see Git.version_ok?)
    GIT_VERSION = [1,6,4,2]

    # The internal Grit::Repo
    attr_reader :grit

    # The gitgo branch
    attr_reader :branch
    
    # The in-memory working tree tracking any adds and removes
    attr_reader :tree
    
    # Returns the sha for the branch
    attr_reader :head
    
    # The path to the instance working directory
    attr_reader :work_dir
    
    # The path to the temporary working tree
    attr_reader :work_tree
    
    # The path to the temporary index_file
    attr_reader :index_file
    
    # The default blob mode for self (see DEFAULT_BLOB_MODE)
    attr_reader :default_blob_mode
    
    # The default tree mode for self (see DEFAULT_TREE_MODE)
    attr_reader :default_tree_mode
    
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
      self.default_blob_mode = options[:default_blob_mode] || DEFAULT_BLOB_MODE
      self.default_tree_mode = options[:default_tree_mode] || DEFAULT_TREE_MODE
    end
    
    # Sets the default blob mode
    def default_blob_mode=(mode)
      @default_blob_mode = mode.to_sym
    end
    
    # Sets the default tree mode
    def default_tree_mode=(mode)
      @default_tree_mode = mode.to_sym
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
    def [](path, entry=false, committed=false)
      tree = committed ? commit_tree : @tree
      
      segments = split(path)
      unless basename = segments.pop
        return entry ? tree : tree.keys
      end
      
      unless tree = tree.subtree(segments)
        return nil 
      end
      
      obj = tree[basename]
      return obj if entry
      
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
    
    # Sets branch to track the specified upstream_branch.  The upstream_branch
    # must be an existing tracking branch; an error is raised if this
    # requirement is not met (see the Tracking, Push/Pull notes above).
    def track(upstream_branch)
      if upstream_branch.nil?
        # currently grit.config does not support unsetting (grit-2.0.0)
        grit.git.config({:unset => true}, "branch.#{branch}.remote")
        grit.git.config({:unset => true}, "branch.#{branch}.merge")
      else
        unless tracking_branch?(upstream_branch)
          raise "the upstream branch is not a tracking branch: #{upstream_branch}"
        end
        
        remote, remote_branch = upstream_branch.split('/', 2)
        grit.config["branch.#{branch}.remote"] = remote
        grit.config["branch.#{branch}.merge"] = "refs/heads/#{remote_branch}"
      end
    end
    
    # Returns the upstream_branch as setup by track.  Raises an error if the
    # 'branch.name.merge' config doesn't follow the pattern 'ref/heads/branch'
    # (see the Tracking, Push/Pull notes above).
    def upstream_branch
      remote = grit.config["branch.#{branch}.remote"]
      merge  = grit.config["branch.#{branch}.merge"]
      
      # No remote, no merge, no tracking.
      if remote.nil? || merge.nil?
        return nil
      end
      
      unless merge =~ /^refs\/heads\/(.*)$/
        raise "invalid upstream branch"
      end
      
      "#{remote}/#{$1}"
    end
    
    # Returns the remote as setup by track, or origin if tracking has not been
    # setup.
    def remote
      grit.config["branch.#{branch}.remote"] || 'origin'
    end
    
    # Returns true if the specified ref is a tracking branch, ie it is the
    # name of an existing remote ref.
    def tracking_branch?(ref)
      ref && grit.remotes.find {|remote| remote.name == ref }
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
    # when you know there are changes to commit and don't want the overhead of
    # checking for changes.
    def commit!(message, options={})
      now = Time.now
      
      sha = options.delete(:tree) || tree.write_to(self).at(1)
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
      lines << "tree #{sha}"
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

    # Sets the current branch and updates tree.
    #  
    # Checkout does not actually checkout any files unless a block is given. 
    # In that case, the current branch will be checked out for the duration of
    # the block into work_tree; a gitgo-specific directory distinct from the
    # user's working directory. Checkout with a block permits the execution of
    # git commands that must be performed in a working directory.
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
    def fetch(remote=self.remote)
      sandbox {|git,w,i| git.fetch({}, remote) }
      self
    end
    
    # Returns true if a merge update is available for branch.
    def merge?(treeish=upstream_branch)
      sandbox do |git, work_tree, index_file|
        des, src = safe_rev_parse(branch, treeish)
        
        case
        when src.nil? then false
        when des.nil? then true
        else des != src && git.merge_base({}, des, src).chomp("\n") != src
        end
      end
    end
    
    # Merges the specified reference with the current branch, fast-forwarding
    # when possible.  This method does not need to checkout the branch into a
    # working directory to perform the merge.
    def merge(treeish=upstream_branch)
      sandbox do |git, work_tree, index_file|
        des, src = safe_rev_parse(branch, treeish)
        base = des.nil? ? nil : git.merge_base({}, des, src).chomp("\n")
        
        case
        when base == src
          break
        when base == des
          # fast forward situation
          grit.update_ref(branch, src)
        else
          # todo: add rebase as an option
          
          git.read_tree({
            :m => true,          # merge
            :i => true,          # without a working tree
            :trivial => true,    # only merge if no file-level merges are required
            :aggressive => true, # allow resolution of removes
            :index_output => index_file
          }, base, branch, src)
          
          commit!("gitgo merge of #{treeish} into #{branch}", 
            :tree => git.write_tree.chomp("\n"),
            :parents => [des, src]
          )
        end
        
        reset
      end
      
      self
    end
    
    # Pushes branch to the tracking branch.  No other branches are pushed. 
    # Raises an error if given a non-tracking branch (see the Tracking,
    # Push/Pull notes above).
    def push(tracking_branch=upstream_branch)
      sandbox do |git, work_tree, index_file|
        remote, remote_branch = parse_tracking_branch(tracking_branch)
        git.push({}, remote, "#{branch}:#{remote_branch}") unless head.nil?
      end
    end
    
    # Fetches the tracking branch and merges with branch. No other branches
    # are fetched. Raises an error if given a non-tracking branch (see the
    # Tracking, Push/Pull notes above).
    def pull(tracking_branch=upstream_branch)
      sandbox do |git, work_tree, index_file|
        remote, remote_branch = parse_tracking_branch(tracking_branch)
        git.fetch({}, remote, "#{remote_branch}:remotes/#{tracking_branch}")
        merge(tracking_branch)
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
          raise "could not resolve to a sha: #{shas.last}"
        end
        
        shas
      end
    end
    
    # Same as rev_parse but always returns an array.  Arguments that cannot be
    # converted to a valid sha will be represented by nil.  This method is
    # slower than rev_parse because it converts arguments one by one
    def safe_rev_parse(*args)
      args.collect! {|arg| rev_parse(arg).at(0) rescue nil }
    end
    
    # Returns an array of revisions (commits) reachable from the treeish.
    def rev_list(*treeishs)
      return treeishs if treeishs.empty?
      sandbox {|git,w,i| git.run('', :rev_list, '', {}, treeishs).split("\n") }
    end
    
    # Retuns an array of added, deleted, and modified files keyed by 'A', 'D',
    # and 'M' respectively.
    def diff_tree(a, b="^#{a}")
      sandbox do |git,w,i|
        output = git.run('', :diff_tree, '', {:r => true, :name_status => true}, [a, b])
        
        diff = {'A' => [], 'D' => [], 'M' => []}
        output.split("\n").each do |line|
          mode, path = line.split(' ', 2)
          array = diff[mode] or raise "unexpected diff output:\n#{output}"
          array << path
        end

        diff
      end
    end
    
    # Returns an array of paths at the specified treeish.
    def ls_tree(treeish)
      sandbox do |git,w,i|
        git.run('', :ls_tree, '', {:r => true, :name_only => true}, [treeish]).split("\n")
      end
    end
    
    # Greps for paths matching the pattern, at the specified treeish.  Each
    # matching path and blob are yielded to the block.
    #
    # Instead of a pattern, a hash of grep options may be provided.  The
    # following options are allowed:
    #
    #   :ignore_case
    #   :invert_match
    #   :fixed_strings
    #   :e
    #
    def grep(pattern, treeish=head) # :yields: path, blob
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
    
    # Greps for trees matching the pattern, at the specified treeish.  Each
    # matching path and tree are yielded to the block.
    #
    # Instead of a pattern, a hash of grep options may be provided.  The
    # following options are allowed:
    #
    #   :ignore_case
    #   :invert_match
    #   :fixed_strings
    #   :e
    #
    def tree_grep(pattern, treeish=head) # :yields: path, tree
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
    
    # Greps for commits with messages matching the pattern, starting at the
    # specified treeish.  Each matching commit yielded to the block.
    #
    # Instead of a pattern, a hash of git-log options may be provided.
    def commit_grep(pattern, treeish=head) # :yields: commit
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
    
    # Creates and sets a work tree and index file so that git will have an
    # environment it can work in.  Specifically sandbox creates an empty
    # work_tree and index_file, the sets these ENV variables:
    #
    #  GIT_DIR:: set to the repo path
    #  GIT_WORK_TREE:: work_tree,
    #  GIT_INDEX_FILE:: index_file
    #
    # Once these are set, sandbox yields grit.git, the work_tree, and
    # index_file to the block. After the block returns, the work_tree and
    # index_file are removed.  Nested calls to sandbox will reuse the previous
    # sandbox and yield immediately to the block.
    #
    # Note that no content is checked out into work_tree or index_file by this
    # method; that must be done as needed within the block.
    def sandbox # :yields: git, work_tree, index_file
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

    def parse_tracking_branch(ref) # :nodoc:
      unless tracking_branch?(ref)
        raise "not a tracking branch: #{ref.inspect}"
      end

      ref.split('/', 2)
    end
    
    def convert_to_entry(content) # :nodoc:
      case content
      when String then [default_blob_mode, set(:blob, content)]
      when Symbol then [default_blob_mode, content]
      when Array, nil then content
      else raise "invalid content: #{content.inspect}"
      end
    end
    
    def commit_tree # :nodoc:
      tree = head ? get(:commit, head).tree : nil
      Tree.new(tree)
    end
  end
end