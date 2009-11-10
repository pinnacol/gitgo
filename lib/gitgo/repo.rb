require 'grit'
require 'gitgo/document'
require 'gitgo/patches/grit'
require 'gitgo/repo/tree'
require 'gitgo/repo/index'

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
          unless options[:is_bare] || path =~ /\.git$/
            path = File.join(path, ".git")
          end

          git = Grit::Git.new(path)
          git.init({})
        end

        new(path, options)
      end
    end
    include Enumerable
    
    DEFAULT_BRANCH = 'gitgo'
    WORK_TREE = 'gitgo'

    DEFAULT_BLOB_MODE = :"100644"
    DEFAULT_TREE_MODE = :"040000"

    YEAR = /\A\d{4,}\z/
    MMDD = /\A\d{4}\z/

    # The internal Grit::Repo
    attr_reader :grit

    # The active branch/commit name
    attr_reader :branch

    # The in-memory working tree tracking any adds and removes.
    attr_reader :tree

    # Initializes a new Git for the repo at the specified path.
    # Raises an error if no such repo exists.  Options can specify the
    # following:
    #
    #   :branch     the branch for self
    #   :author       the author for self
    #   + any Grit::Repo options
    #
    def initialize(path=Dir.pwd, options={})
      @grit = path.kind_of?(Grit::Repo) ? path : Grit::Repo.new(path, options)
      @branch = options[:branch] || DEFAULT_BRANCH
      self.author = options[:author]
      reset
    end
    
    # Returns the current commit for branch.
    def current
      grit.commits(branch, 1).first
    end
    
    # Returns the specified path relative to the git repo (ie the .git
    # directory as indicated by grit.path).  With no arguments path returns
    # the git repo path.
    def path(*paths)
      File.join(grit.path, *paths)
    end
    
    def index_path(*paths)
      File.join(grit.path, WORK_TREE, "idx", *paths)
    end
    
    def work_path(*paths)
      File.join(grit.path, WORK_TREE, "db", *paths)
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
        
        content = paths[path]
        content = [DEFAULT_BLOB_MODE, set(:blob, content)] if content.kind_of?(String)
        
        tree = @tree.subtree(segments, true)
        tree[basename] = content
        
        paths[path] = content if update
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
    
    def commit(message, options={})
      raise "no changes to commit" if status.empty?
      commit!(message, options)
    end
    
    # Commits the current tree to branch with the specified message.  The
    # branch is created if it doesn't already exist.
    def commit!(message, options={})
      mode, id = write_tree(tree)
      now = Time.now
      parent = self.current
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
      lines << "tree #{id}"
      lines << "parent #{parent.id}" if parent
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
      lines << ""

      id = set(:commit, lines.join("\n"))
      File.open(path("refs/heads/#{branch}"), "w") {|io| io << id }
      id
    end
    
    # Resets the working tree.
    def reset
      @tree = commit_tree
    end

    # Returns a hash of (path, state) pairs indicating paths that have been
    # added or removed.  State must be :add or :rm.
    def status
      a = commit_tree.flatten
      b = tree.flatten
      
      diff = {}
      (a.keys | b.keys).each do |key|
        in_a = a.has_key?(key)
        in_b = b.has_key?(key)
        
        case
        when in_a && in_b
          diff[key] = :mod if a[key] != b[key]
        when in_a
          diff[key] = :rm
        when in_b
          diff[key] = :add
        end
      end
      diff
    end

    # Sets the current branch and updates index.  Checkout will also
    # checkout self into the directory specified by path, if specified.
    def checkout(branch, path=nil, options={})
      if path
        FileUtils.mkdir_p(path) unless File.exists?(path)
        grit.git.run("GIT_WORK_TREE='#{path}' ", :checkout, '', options, @branch)
      end
      
      if branch && branch != @branch
        @branch = branch
        reset
      end
    end

    # Pulls from the remote into the work tree.
    def pull(remote="origin", rebase=true)
      git(:pull, remote, :rebase => rebase)
      reset
    end

    # Clones self into the specified path and sets up tracking of branch in
    # the new grit.  Clone was primarily implemented for testing; normally
    # clones are managed by the user.
    def clone(path, options={})
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
    
    def gc
      grit.git.gc
      # this nasty reinitialization is required at this point because grit
      # apparently caches the packs... once you gc the packs change and
      # Grit::GitRuby bombs.  Maybe something more succinct could be done with
      # GitRuby#file_index and GitRuby#ruby_git ?
      @grit = Grit::Repo.new(path, :is_bare => grit.bare)
      reset
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
      
      each_index(doc) do |path|
        Index.write(path, id)
      end
      
      id
    end

    def index(key, value, n=10, start=0)
      idx_file = index_path(key, value)
      
      if File.exists?(idx_file)
        Index.open(idx_file) {|idx| idx.read(n, start) }
      else
        []
      end
    end

    # Gets the document indicated by id, or nil if no such document exists.
    def read(id)
      blob = grit.blob(id)
      blob.data.empty? ? nil : Document.parse(blob.data, id)
    end
    
    # Updates the content of the specified document and reassigns all links
    # to the document.
    def update(id, content, attrs={})
      return nil unless old_doc = read(id)

      parents = self.parents(id)
      children = self.children(id)
      new_doc = old_doc.merge(attrs, content)

      parents.each {|parent| unlink(parent, id) }
      children.each {|child| unlink(id, child) }
      rm timestamp(old_doc.date, id)

      id = store(new_doc)
      parents.each {|parent| link(parent, id) }
      children.each {|child| link(id, child) }

      new_doc.sha = id
      new_doc
    end

    # Removes the document from the repo by deleting it from the timeline.
    def destroy(id)

      # Destroying a doc with children is a bad idea because there is no one
      # good way of removing the children.  Children with multiple parents
      # should not be unlinked recursively.  Children with no other parents
      # should be unlinked and destroyed (because nothing will reference them
      # anymore).
      #
      # Note the same is not true for parents; a doc can simply remove itself
      # from the parents, each of which will remain valid afterwards.
      unless children(id).empty?
        raise "cannot destroy a document with children"
      end

      return nil unless doc = read(id)

      parents(id).each {|parent| unlink(parent, id) }
      rm timestamp(doc.date, id)

      doc
    end

    # Yields each document in the repo, ordered by date (with day resolution).
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
        if offset > 0
          offset -= 1
        else
          shas << sha
          break if n && shas.length == n
        end
      end
      shas
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
    def ref(parent, child, options={})
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
    
    def reindex!(full=false)
      indexes = Hash.new do |hash, path|
        hash[path] = File.exists?(path) ? Index.read(path) : []
      end
      
      previous = indexes[index_log]
      current = collect {|sha| sha }
      
      previous.clear if full
      
      # adds
      (current - previous).each do |sha|
        each_index(read(sha)) {|path| indexes[path] << sha }
      end
      
      # removes
      (previous - current).each do |sha|
        each_index(read(sha)) {|path| indexes[path].delete(sha) }
      end
      
      indexes.each_pair do |path, shas|
        shas.uniq!
        Index.write(path, shas.join, "w")
      end
      
      self
    end
    
    protected

    # executes the git command in the working tree
    def git(cmd, *args) # :nodoc:
      work_path = self.work_path
      checkout(nil, work_path) unless File.exists?(work_path)

      # chdir + setting the work tree may seem redundant, but it's not in the
      # case of a bare gritsitory because:
      # * some operations need to be done in the work tree
      # * git will guess the parent dir of the grit if no work tree is set
      #
      Dir.chdir(work_path) do
        options = args.last.kind_of?(Hash) ? args.pop : {}
        grit.git.run("GIT_WORK_TREE='#{work_path}' ", cmd, '', options, args)
      end
    end
    
    # Returns the sha for an empty file.  Note this only needs to be
    # initialized once for a given repo; even if you change branches the
    # object will be in the repo.
    def empty_sha # :nodoc:
      @empty_sha ||= set(:blob, "")
    end
    
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
    
    def path_segments(path) # :nodoc:
      segments = path.kind_of?(String) ? path.split("/") : path.dup
      segments.shift if segments[0] && segments[0].empty?
      segments.pop   if segments[-1] && segments[-1].empty?
      segments
    end
    
    def commit_tree # :nodoc:
      commit = current
      commit ? Tree.new(commit.tree) : Tree.new
    end
    
    # tree format:
    #---------------------------------------------------
    #   mode name\0[packedsha]mode name\0[packedsha]...
    #---------------------------------------------------
    # note there are no newlines separating tree entries.
    def write_tree(tree)
      tree_mode = tree.mode ||= DEFAULT_TREE_MODE
      tree_id   = tree.sha  ||= begin
        lines = []
        tree.each_pair(false) do |key, entry|
          mode, id = case entry
          when Tree  then write_tree(entry)
          when Array then entry
          else [entry.mode, entry.id]
          end

          lines << "#{mode} #{key}\0#{[id].pack("H*")}"
        end
        
        set(:tree, lines.join)
      end
      
      [tree_mode, tree_id]
    end
    
    def index_log # :nodoc:
      path("index")
    end
    
    def each_index(doc) # :nodoc:
      doc.attributes(false).each_pair do |key, values|
        values = [values] unless values.kind_of?(Array)
        
        values.each do |value|
          yield(index_path(key, value))  if value
        end
      end
      
      email = doc.author.email
      yield(index_path('author', email)) if email
      yield(index_log)
    end
  end
end