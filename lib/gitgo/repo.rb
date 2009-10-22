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
  #   repo = Repo.init("example", :user => "John Doe <jdoe@example.com>")
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
  # ==== The Working Tree
  #
  # Changes to the repo are tracked by tree until being committed. Tree is a
  # hash of (path, [mode, sha]) pairs representing the tree contents.  Symbol
  # paths indicate a subtree that could be expanded.
  #
  #   repo.branch = "gitgo"
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
  # As you can see, subtrees also track the mode for the subtree.  Note that the expanded
  # subtrees have not been written to the repo and so they don't have id at this point
  # (this echos what happens when you stage changes with 'git add' but have yet to commit
  # the changes with 'git commit').
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
      # Initializes a Repo for path, creating the repo if necessary.
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
    attr_reader :repo
    
    # The active branch/commit name
    attr_reader :branch
    
    # The internal tree tracking any adds and removes.
    attr_reader :tree
    
    # Flag to rebase on pull (default true).  It is technically safer to set
    # rebase to false on pulls rather than rebase, but it results in a
    # nonlinear history and for, as far as I know, no real benefit given the
    # Gitgo data model.
    attr_reader :rebase
    
    # Initializes a new repo at the specified path.  Raises an error if no
    # such repo exists.  Options can specify the following:
    #
    #   :branch     the branch for self
    #   :user       the user for self
    #   :rebas      flags rebase on pull
    #   + any Grit::Repo options
    #
    def initialize(path=Dir.pwd, options={})
      options = {
        :branch => DEFAULT_BRANCH,
        :user => nil,
        :rebase => true
      }.merge(options)
      
      @repo = path.kind_of?(Grit::Repo) ? path : Grit::Repo.new(path, options)
      self.branch = options[:branch]
      self.user = options[:user]
      @rebase = options[:rebase]
    end
    
    # Returns the specified path relative to the git repo (ie the .git
    # directory as indicated by repo.path).  With no arguments path returns
    # the git repo path.
    def path(*paths)
      File.join(repo.path, *paths)
    end
    
    # Returns a path relative to the gitgo work tree (.git/gitgo).  With no
    # arguments work_path returns the path to the work tree.
    def work_path(*paths)
      File.join(repo.path, WORK_TREE, *paths)
    end
    
    # Returns the current commit for branch.
    def current
      repo.commits(branch, 1).first
    end
    
    # Sets the current branch and updates tree.
    def branch=(branch)
      @branch = branch
      @tree = get_tree("/") || tree_hash
    end
    
    # Returns the configured user (which should be a Grit::Actor, or similar).
    # If no user is is currently set, a default user will be determined from
    # the repo configurations.
    def user
      @user ||= begin
        name =  repo.config['user.name']
        email = repo.config['user.email']
        Grit::Actor.new(name, email)
      end
    end
    
    # Sets the user.  The input may be a Grit::Actor, an array like [user,
    # email], a git-formatted user string (ex 'John Doe <jdoe@example.com>'),
    # or nil.
    def user=(input)
      @user = case input
      when Grit::Actor, nil then input
      when Array  then Grit::Actor.new(*input)
      when String then Grit::Actor.from_string(*input)
      else raise "could not convert to Grit::Actor: #{input.class}"
      end
    end
    
    # Gets the object at the specified path
    def get(path)
      return nil unless current = self.current
      current = current.tree

      segments(path) do |seg|
        return nil unless current.respond_to?(:/)
        current = current / seg
      end
      
      current
    end
    
    # Gets the content for path.  Returns nil if path doesn't exist (or maps
    # to a tree).
    def [](path)
      obj = get(path)
      
      case obj
      when Grit::Blob then obj.data
      when Grit::Tree then obj.contents.collect {|content| content.name }
      else nil
      end
    end
    
    # Sets content for path.
    def []=(path, content=nil)
      if content.nil?
        rm(path)
      else
        add(path => content)
      end
    end
    
    # Write a raw object to the repository and returns the object id.  This
    # method is patterned after GitStore#write
    def write(type, content)
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
    
    def doc(sha)
      blob = repo.blob(sha)
      blob.data.empty? ? nil : Document.new(blob.data, sha)
    end
    
    def create(content, attrs={})
      attrs['content'] = content
      attrs['author'] ||= user
      attrs['date'] ||= Time.now
      
      write("blob", Document.new(attrs).to_s)
    end
    
    # Returns the type of the object identified by sha.
    def type(sha)
      repo.git.cat_file({:t => true}, sha)
    end
    
    # Commits the current tree to branch with the specified message.  The
    # branch is created if it doesn't already exist.
    def commit(message, options={})
      raise "no changes to commit" if status.empty?
      
      repo_path = path("refs/heads/#{branch}")
      
      mode, tree_id = write_tree
      parent = self.current
      author = options[:author] || user
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
      lines << "tree #{tree_id}"
      lines << "parent #{parent.id}" if parent
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
      lines << ""
      
      id = write('commit', lines.join("\n"))
      File.open(repo_path, "w") {|io| io << id }
      @tree = get_tree("/")
      id
    end
    
    def status
      diff_tree
    end
    
    def add(files)
      files.each_pair do |path, content|
        tree = @tree
        base = segments(path, true) do |seg|
          tree.delete(seg.to_sym)
          tree = tree[seg]
        end
        
        entry = case content
        when Array, Hash
          content
        else 
          [DEFAULT_BLOB_MODE, write("blob", content)]
        end 
        
        entry[2] = :add
        tree[base] = entry
      end
      
      self
    end
    
    def rm(*paths)
      paths.each do |path|
        tree = @tree
        segments(path) do |seg|
          tree.delete(seg.to_sym)
          tree = tree[seg]
        end
        
        tree[2] = :rm
        
        if tree.kind_of?(Hash)
          recursive_paths = keys(tree).collect! {|key| File.join(path, key) }
          rm(*recursive_paths)
        end
      end
      
      self
    end
    
    # Links the parent and child by adding a reference to the child under the
    # sha-path for the parent.
    def link(parent, child, options={})
      path = options[:as] || child
      mode = options[:mode] || DEFAULT_BLOB_MODE
      
      add(sha_path(parent, path) => [mode, child])
      self
    end

    # Returns an array of references under sha-path for the parent.  If
    # recursive is specified, links will recursively seek links for each
    # child.  In that case links returns a nested hash of linked shas.
    def links(parent, options={}, &block)
      links = self[sha_path(parent)] || []
      
      unless options[:recursive]
        links.collect!(&block) if block_given?
        return links
      end
      
      visited = options[:visited] ||= [parent]
      
      tree = {}
      links.each do |child|
        circular = visited.include?(child)
        visited.push child
        
        if circular
          raise "circular link detected:\n  #{visited.join("\n  ")}\n"
        end
        
        key = block_given? ? yield(child) : child
        tree[key] = links(child, options, &block)
        visited.pop
      end
      
      tree
    end

    # Unlinks the parent and child by removing the reference to the child
    # under the sha-path for the parent.  Unlink will recursively remove all
    # links to the child if specified.
    def unlink(parent, child, options={})
      rm(sha_path(parent, options[:as] || child))

      links(child).each do |grandchild|
        unlink(child, grandchild, options)
      end if options[:recursive]

      self
    end
    
    # Registers the object to the specified type by adding a reference to the
    # sha under the type directory.
    def register(type, sha, options={})
      mode = options[:mode] || DEFAULT_BLOB_MODE
      path = options[:flat] ? File.join(type, sha) : registry_path(type, sha)
      
      add(path => [mode, sha])
      self
    end
    
    # Returns a list of shas registered to the type.
    def registry(type, options={})
      tree = self[type] || []
      
      return tree if options[:flat]
      
      shas = []
      tree.each do |ab|
        self[File.join(type, ab)].each do |xyz|
          shas << ab + xyz
        end
      end
      shas
    end
    
    # Unregisters the sha to the type by removing the reference to the sha
    # under the type directory.  Unregister will recursively remove all links
    # to the sha if specified.
    def unregister(type, sha, options={})
      path = options[:flat] ? File.join(type, sha) : registry_path(type, sha)
      rm(path)

      links(sha).each do |child|
        unlink(sha, child, options)
      end if options[:recursive]

      self
    end
    
    # Checks out self into the directory specified by path.
    def checkout(path=work_path)
      FileUtils.mkdir_p(path) unless File.exists?(path)
      repo.git.run("GIT_WORK_TREE='#{path}' ", :checkout, '', {}, branch)
    end
    
    # Pulls from the remote into the work tree.
    def pull(remote="origin", rebase=self.rebase)
      git(:pull, remote, :rebase => rebase)
    end
    
    # Clones self into the specified path and sets up tracking of branch in
    # the new repo.  Clone was primarily implemented for testing; normally
    # clones are managed by the user.
    def clone(path, options={})
      repo.git.clone(options, repo.path, path)
      clone = Grit::Repo.new(path)
      
      if options[:bare]
        # bare origins directly copy branch heads without mapping them to
        # 'refs/remotes/origin/' (see git-clone docs). this maps the branch
        # head so the bare repo can checkout branch
        clone.git.remote({}, "add", "origin", repo.path)
        clone.git.fetch({}, "origin")
        clone.git.branch({}, "-D", branch)
      end
      
      # sets up branch to track the origin to enable pulls
      clone.git.branch({:track => true}, branch, "origin/#{branch}")
      Repo.new(clone, :branch => branch, :user => user)
    end
    
    protected
    
    # executes the git command in the working tree
    def git(cmd, *args) # :nodoc:
      checkout unless File.exists?(work_path)
      
      # chdir + setting the work tree may seem redundant, but it's not in the
      # case of a bare repository because:
      # * some operations need to be done in the work tree
      # * git will guess the parent dir of the repo if no work tree is set
      #
      Dir.chdir(work_path) do
        options = args.last.kind_of?(Hash) ? args.pop : {}
        repo.git.run("GIT_WORK_TREE='#{work_path}' ", cmd, '', options, args)
      end
    end
    
    def sha_path(sha, *paths) # :nodoc:
      File.join(sha[0,2], sha[2,38], *paths)
    end
    
    def registry_path(type, sha) # :nodoc:
      File.join(type, sha[0,2], sha[2,38])
    end
    
    # splits path and yields each path segment to the block.  if specified,
    # the basename will be returned instead of being yielded to the block.
    def segments(path, return_basename=false) # :nodoc:
      paths = path.kind_of?(String) ? path.split("/") : path.dup
      last = return_basename ? paths.pop : nil
      
      while seg = paths.shift
        next if seg.empty?
        yield(seg)
      end
      
      last
    end
    
    def get_tree(path) # :nodoc:
      obj = get(path)
      
      case obj
      when Grit::Tree
        tree = tree_hash(path)
        tree[0] = obj.mode if obj.mode
        # tree[1] = obj.id
        
        obj.contents.each do |object|
          key = object.name
          key = key.to_sym if object.kind_of?(Grit::Tree)
          tree[key] = [object.mode, object.id]
        end
        
        tree
        
      when Grit::Blob
        [obj.mode, obj.id]
      
      else obj
      end
    end
    
    def write_tree(tree=@tree) # :nodoc:
      
      # tree format:
      #---------------------------------------------------
      #   mode name\0[packedsha]mode name\0[packedsha]...
      #---------------------------------------------------
      # note there are no newlines separating tree entries.
      lines = keys(tree).sort_by do |key|
        key.to_s
      end.collect! do |key|
        value = tree[key]
        value = write_tree(value) if value.kind_of?(Hash)
        
        mode, id, flag = value
        next if flag == :rm
        
        "#{mode} #{key}\0#{[id].pack("H*")}"
      end
      
      [tree[0] || DEFAULT_TREE_MODE, write("tree", lines.join)]
    end
    
    def diff_tree(tree=@tree, target={}, path=nil) # :nodoc:
      keys(tree).each do |key|
        value = tree[key]
        key = File.join(path, key.to_s) if path
        
        case
        when value.kind_of?(Hash)
          diff_tree(value, target, key)
        when state = value[2]
          target[key] = state
        end
      end
      
      target
    end
    
    def tree_hash(path=nil) # :nodoc:
      Hash.new do |hash, key|
        next if key.kind_of?(Integer)
        
        tree = path ? get_tree(File.join(path, key)) : nil
        hash[key] = tree || tree_hash
      end
    end
    
    def keys(tree) # :nodoc:
      tree.keys.delete_if do |key|
        key.kind_of?(Integer)
      end
    end
    
  end
end