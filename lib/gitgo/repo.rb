require 'grit'
require 'gitgo/document'
require 'gitgo/patches/grit'

module Gitgo
  
  # A wrapper to a Grit::Repo that allows access and modification of
  # repository data by path, without checking the repository out.  The api is
  # patterned after commands you'd invoke on the command line.  Several key
  # methods of this class are patterned after
  # {GitStore}[http://github.com/georgi/git_store] (see license below). 
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
  # Changes to the repo are tracked by tree until being committed. Tree is a
  # hash of (path, [mode, sha]) pairs representing the in-memory working tree
  # contents. Symbol paths indicate a subtree that could be expanded.
  #
  #   repo = Repo.init("example", :author => "John Doe <jdoe@example.com>")
  #   repo.add(
  #     "README" => "New Project",
  #     "lib/project.rb" => "module Project\nend"
  #   ).commit("added files")
  #
  #   repo.tree
  #   # => {
  #   #   "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   :lib     => ["040000", "cad0dc0df65848aa8f3fee72ce047142ec707320"]
  #   # }
  #
  # When the repo adds or removes content, the subtrees are expanded as needed
  # to show the changes.
  #
  #   repo.add("lib/project/utils.rb" => "module Project\n  module Utils\n  end\nend")
  #   repo.tree
  #   # => {
  #   #   "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1"],
  #   #   "lib"    => {
  #   #     0 => "040000"
  #   #     "project.rb" => ["100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
  #   #     "project" => {
  #   #       0 => "040000",
  #   #       "utils" => ["100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4", :add]
  #   #     }
  #   #   }
  #   # }
  #
  #   repo.rm("README")
  #   repo.tree
  #   # => {
  #   #   "README" => ["100644", "73a86c2718da3de6414d3b431283fbfc074a79b1", :rm],
  #   #   "lib"    => {
  #   #     0 => "040000",
  #   #     "project.rb" => ["100644", "636e25a2c9fe1abc3f4d3f380956800d5243800e"],
  #   #     "project" => {
  #   #       0 => "040000",
  #   #       "utils.rb" => ["100644", "c4f9aa58d6d5a2ebdd51f2f628b245f9454ff1a4", :add]
  #   #     }
  #   #   }
  #   # }
  #
  # As you can see, subtrees also track the mode for the subtree.  Note that
  # the expanded subtrees have not been written to the repo and so they don't
  # have id at this point (this echos what happens when you stage changes with
  # 'git add' but have yet to commit the changes with 'git commit').
  #
  # A summary of the blobs that have changed can be obtained via status:
  #
  #   repo.status
  #   # => {
  #   #   "README" => :rm
  #   #   "lib/project/utils.rb" => :add
  #   # }
  #
  # == {GitStore}[http://github.com/georgi/git_store] License
  #
  # Copyright (c) 2008 Matthias Georgi <http://www.matthias-georgi.de>
  #            
  # Permission is hereby granted, free of charge, to any person obtaining a
  # copy of this software and associated documentation files (the "Software"),
  # to deal in the Software without restriction, including without limitation
  # the rights to use, copy, modify, merge, publish, distribute, sublicense,
  # and/or sell copies of the Software, and to permit persons to whom the
  # Software is furnished to do so, subject to the following conditions:
  #            
  # The above copyright notice and this permission notice shall be included in
  # all copies or substantial portions of the Software.
  #            
  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
  # THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
  # IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
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
    
    DEFAULT_BRANCH = 'gitgo'
    WORK_TREE = 'gitgo'

    DEFAULT_BLOB_MODE = "100644"
    DEFAULT_TREE_MODE = "040000"

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
      @tree = commit_tree
      
      self.author = options[:author]
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
    
    # Sets an object into the git repository and returns the object id.  This
    # method is patterned after GitStore#write.
    def set(type, content) # :nodoc:
      data = "#{type} #{content.length}\0#{content}"
      id = Digest::SHA1.hexdigest(data)[0, 40]
      path = self.path("/objects/#{id[0...2]}/#{id[2..39]}")

      unless File.exists?(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'wb') do |io|
          io.write Zlib::Deflate.deflate(data)
        end
      end

      id
    end
    
    # Gets the content for path; either the blob data or an array of content
    # names for a tree.  Returns nil if path doesn't exist.
    #
    # (path should be the path to the file without leading or trailing /)
    def [](path, committed=false)
      tree = committed ? commit_tree : @tree
      
      segments = path_segments(path)
      unless basename = segments.pop
        return keys(tree)
      end
      
      unless tree = subtree(tree, segments)
        return nil 
      end
      
      obj = entry(tree, basename)
      case obj
      when Array then get(:blob, obj[1]).data
      when Hash  then keys(obj)
      else nil
      end
    end

    # Sets content for path. Content may be:
    #
    # * a string of content
    # * an array like [mode, sha] (for blobs)
    # * a hash of (path, [mode, sha]) pairs (for trees)
    #
    def []=(path, content=nil)
      if content.nil?
        rm(path)
      else
        add(path => content)
      end
    end
    
    # Adds content at the specified paths.  Takes a hash of (path, content)
    # pairs where the content can either be:
    #
    # * a string of content
    # * an array like [mode, sha] (for blobs)
    # * a hash of (path, [mode, sha]) pairs (for trees)
    #
    # If update is true, then string contents will be updated with a
    # [mode, sha] array representing the new blob.
    def add(paths, update=true)
      paths.keys.each do |path|
        segments = path_segments(path)
        unless basename = segments.pop
          raise "invalid path: #{path.inspect}"
        end
        
        content = paths[path]
        if content.kind_of?(String)
          content = [DEFAULT_BLOB_MODE, set(:blob, content)]
        end
        
        tree = subtree(@tree, segments, true)
        tree[basename] = content
        
        paths[path] = content if update
      end

      self
    end
    
    # Removes the content at each of the specified paths
    def rm(*paths)
      paths.each do |path|
        segments = path_segments(path)
        unless basename = segments.pop
          raise "invalid path: #{path.inspect}"
        end
        
        if tree = subtree(@tree, segments)
          tree.delete(basename.to_sym)
          tree.delete(basename)
        end
      end

      self
    end
    
    # Links the parent and child by adding a reference to the child under the
    # sha path for the parent.
    #
    # Note that only blobs and trees should be linked as children; other
    # object types (ex commit, tag) will be seen as corruption by git. 
    # Parents can refer to any object.
    def link(parent, child, options={})
      add(sha_path(options, parent, child) => [DEFAULT_BLOB_MODE, empty_sha])
      self
    end


    # Returns an array of parents that link to the child.
    def parents(child, options={})
      segments = path_segments(options[:dir] || "/")
      
      parents = []
      return parents unless tree = subtree(@tree, segments)
      
      # seek /ab/xyz/sha where sha == child
      tree.keys.each do |ab|
        ab_tree = entry(tree, ab)
        next unless ab_tree.kind_of?(Hash)
        
        ab_tree.keys.each do |xyz|
          xyz_tree = entry(ab_tree, xyz)
          next unless xyz_tree.kind_of?(Hash)
          
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
    def children(parent, options={}, &block)
      children = self[sha_path(options, parent)] || []

      unless options[:recursive]
        children.collect!(&block) if block_given?
        return children
      end

      visited = options[:visited] ||= [parent]

      tree = {}
      children.each do |child|
        circular = visited.include?(child)
        visited.push child

        if circular
          raise "circular link detected:\n  #{visited.join("\n  ")}\n"
        end

        key = block_given? ? yield(child) : child
        tree[key] = children(child, options, &block)

        visited.pop
      end

      tree
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

    # Creates a new Document using the content and attributes, writes it to
    # the repo and returns it's sha.  New documents are stored by timestamp
    # and logged to their author.
    def create(content, attrs={}, options={})
      attrs['content'] = content
      attrs['author'] ||= author
      attrs['date'] ||= Time.now

      store(Document.new(attrs), options)
    end

    # Stores the document by timestamp and logs the document to the author.
    def store(doc, options={})
      mode = options[:mode] || DEFAULT_BLOB_MODE
      id = set(:blob, doc.to_s)

      add(
        timestamp(doc.date, id) => [mode, id], 
        logfile(doc.author, doc.date) => id
      )

      id
    end

    # Gets the document indicated by id, or nil if no such document exists.
    def read(id)
      blob = grit.blob(id)
      blob.data.empty? ? nil : Document.new(blob.data, id)
    end

    # Updates the content of the specified document and reassigns all links
    # to the document.
    def update(id, attrs={})
      return nil unless old_doc = read(id)

      parents = self.parents(id)
      children = self.children(id)
      new_doc = old_doc.merge(attrs)

      parents.each {|parent| unlink(parent, id) }
      children.each {|child| unlink(id, child) }
      rm timestamp(old_doc.date, id), logfile(old_doc.author, old_doc.date)

      id = store(new_doc)
      parents.each {|parent| link(parent, id) }
      children.each {|child| link(id, child) }

      new_doc.sha = id
      new_doc
    end

    # Removes the document from the repo by deleting it from the timeline.
    # Delete also removes the logfile associating this document with the
    # document author.
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
      rm timestamp(doc.date, id), logfile(doc.author, doc.date)

      doc
    end

    # Returns an array of shas representing recent documents added.
    def timeline(options={})
      options = {:n => 10, :offset => 0}.merge(options)
      offset = options[:offset]
      n = options[:n]

      shas = []
      return shas if n <= 0

      years = (self[index_path] || []).select do |dir|
        dir =~ /\A\d{4,}\z/
      end.sort

      years.reverse_each do |year|

        days = (self[index_path(year)] || []).sort
        days.reverse_each do |day|

          # y,md need to be iterated in reverse to correctly sort by
          # date; this is not the case with the unordered shas
          self[index_path(year, day)].each do |sha|
            if offset > 0
              offset -= 1
            else
              shas << sha
              return shas if n && shas.length == n
            end
          end
        end
      end

      shas
    end

    # Returns an array of shas representing activity by the author.
    def activity(author, options={})
      options = {:n => 10, :offset => 0}.merge(options)
      offset = options[:offset]
      n = options[:n]

      shas = []
      return shas if n <= 0

      author_path = index_path(author.email)
      (self[author_path] || []).sort.reverse_each do |entry|
        if offset > 0
          offset -= 1
        else
          shas << self[File.join(author_path, entry)]
          return shas if n && shas.length == n
        end
      end
      shas
    end

    # Commits the current tree to branch with the specified message.  The
    # branch is created if it doesn't already exist.
    def commit(message, options={})
      raise "no changes to commit" if status.empty?

      mode, id = write_tree(tree)
      parent = self.current
      author = options[:author] || self.author
      authored_date = options[:authored_date] || Time.now
      committer = options[:committer] || author
      committed_date = options[:committed_date] || Time.now

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
      @tree = commit_tree
      id
    end

    # Returns a hash of (path, state) pairs indicating paths that have been
    # added or removed.  State must be :add or :rm.
    def status
      a = flatten_tree(commit_tree)
      b = flatten_tree(tree)
      
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
    def checkout(branch, path=nil)
      if branch && branch != @branch
        @branch = branch
        @tree = commit_tree
      end

      if path
        FileUtils.mkdir_p(path) unless File.exists?(path)
        grit.git.run("GIT_WORK_TREE='#{path}' ", :checkout, '', {}, @branch)
      end
    end

    # Pulls from the remote into the work tree.
    def pull(remote="origin", rebase=true)
      git(:pull, remote, :rebase => rebase)
      @tree = commit_tree
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
    
    protected

    # executes the git command in the working tree
    def git(cmd, *args) # :nodoc:
      work_path = path(WORK_TREE)
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
    def sha_path(options, sha, *paths) # :nodoc:
      paths.unshift sha[2,38]
      paths.unshift sha[0,2]
      
      if dir = options[:dir]
        paths = File.join(dir, *paths)
      end
      
      paths
    end
    
    def index_path(*paths) # :nodoc:
      File.join("/idx", *paths)
    end
    
    def timestamp(date, id) # :nodoc:
      index_path(date.strftime('%Y/%m%d'), id)
    end
    
    def logfile(author, date) # :nodoc:
      date = date.utc
      index_path(author.email, "#{date.to_i}#{date.usec.to_s[0,2]}")
    end
    
    def path_segments(path) # :nodoc:
      segments = path.kind_of?(String) ? path.split("/") : path.dup
      segments.shift if segments[0] && segments[0].empty?
      segments.pop   if segments[-1] && segments[-1].empty?
      segments
    end
    
    def commit_tree # :nodoc:
      commit = current
      commit ? get_tree(commit.tree.id) : {}
    end
    
    def get_tree(id) # :nodoc:
      tree = {}
      get(:tree, id).contents.each do |object|
        key = object.name
        key = key.to_sym if object.kind_of?(Grit::Tree)
        tree[key] = [object.mode, object.id]
      end
      tree
    end
    
    def subtree(tree, segments, force=false) # :nodoc:
      while dir = segments.shift
        next_tree = entry(tree, dir)
        
        if !next_tree.kind_of?(Hash)
          return nil unless force
          
          next_tree = {}
          tree[dir.to_s] = next_tree
        end
        
        tree = next_tree
      end
      tree
    end
    
    def entry(tree, path) # :nodoc:
      entry = tree.delete(path.to_sym)
      
      if entry.kind_of?(Array)
        mode, id = entry
        subtree = get_tree(id)
        subtree[0] = mode
        tree[path.to_s] = subtree
        subtree
      else
        tree[path]
      end
    end
    
    def keys(tree) # :nodoc:
      keys = tree.keys
      keys.delete(0)
      keys.collect {|key| key.to_s }.sort
    end
    
    def write_tree(tree) # :nodoc:

      # tree format:
      #---------------------------------------------------
      #   mode name\0[packedsha]mode name\0[packedsha]...
      #---------------------------------------------------
      # note there are no newlines separating tree entries.
      lines = tree.keys.sort_by do |key|
        key.to_s
      end.collect! do |key|
        next if key == 0
        
        value = tree[key]
        value = write_tree(value) if value.kind_of?(Hash)

        mode, id = value
        "#{mode} #{key}\0#{[id].pack("H*")}"
      end

      [tree[0] || DEFAULT_TREE_MODE, set(:tree, lines.join)]
    end
    
    def flatten_tree(tree, prefix=nil, target={}) # :nodoc:
      tree.keys.each do |key|
        next if key == 0
        next unless value = entry(tree, key)
        
        key = key.to_s
        key = File.join(prefix, key) if prefix
        
        if value.kind_of?(Hash)
          flatten_tree(value, key, target)
        else
          target[key] = value
        end
      end
      
      target
    end
  end
end