require 'grit'

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
  #   repo = Repo.new
  #   repo.checkout "branch", :b => true
  #
  #   repo.add(
  #     "README" => "New Project",
  #     "lib/project.rb" => "module Project\nend",
  #     "remove_this_file" => "won't be here long...")
  #
  #   repo.commit("setup a new project")
  #   repo.current.id                     # => ""
  #
  # Content may be removed as well:
  #
  #   repo.rm("remove_this_file")
  #   repo.commit("removed extra file")
  #   repo.current.id                     # => ""
  #        
  # Now access the content:
  #
  #   repo["/"]
  #   # => {
  #   #  "lib"    => ["040000", ""],
  #   #  "README" => ["100644", ""]
  #   # }
  #
  #   repo["/lib/project.rb"]            # => "module Project\nend"
  #   repo["/remove_this_file"]          # => nil
  #
  # You can go back in time if you wish (but commits won't work unless you're
  # on a valid branch):
  #
  #   repo.branch = ""
  #   repo["/remove_this_file"]          # => "won't be here long..."
  #
  # For access to the Grit objects, use get:
  #
  #   repo.get("/lib").id                # => ""
  #   repo.get("/lib/project.rb").id     # => ""
  #
  # ==== Implementation Notes
  #
  # Changes to the repo are tracked by tree until being committed. Tree is a
  # strange little hash that's designed to allow automatic recursive nesting
  # while preserving whatever is currently in the tree.  
  #
  # For example, to start with tree just shows the contents of the commit
  # tree, indexed by filename:
  #
  #   repo = Repo.new
  #   repo.tree
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
      def init(path, options={})
        unless File.exists?(path)
          if options[:is_bare] || path =~ /\.git$/
            FileUtils.mkdir_p(File.dirname(path))
            `GIT_DIR='#{path}' git init --bare`
          else
            FileUtils.mkdir_p(path)
            Dir.chdir(path) { `git init` }
          end
        end
        
        new(path, options)
      end
    end
    
    DEFAULT_BRANCH = 'gitgo'
    
    # The internal Grit::Repo
    attr_reader :repo
    
    # The active branch/commit name
    attr_reader :branch
    
    # Sets the user.
    attr_writer :user
    
    # The internal tree tracking any adds and removes.
    attr_reader :tree
    
    # Initializes a new repo at the specified path.  Raises an error if no
    # such repo exists.  Options can specify the following:
    #
    #   :branch     the branch for self
    #   :user       the user for self
    #   + any Grit::Repo options
    #
    def initialize(path=".", options={})
      @repo = Grit::Repo.new(path, options)
      self.branch = options[:branch] || DEFAULT_BRANCH
      self.user = options[:user]
    end
    
    # Returns the current commit for branch.
    def current
      repo.commits(branch, 1).first
    end
    
    # Sets the current branch and updates tree.
    def branch=(branch)
      @branch = branch
      @tree = self["/"] || recursive_hash
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
    
    def [](path)
      obj = get(path)
      
      case obj
      when Grit::Tree
        tree = recursive_hash do |key|
          self[File.join(path, key)]
        end
        
        obj.contents.each do |object|
          tree[object.name] = [object.mode, object.id]
        end
        tree
        
      when Grit::Blob
        [obj.mode, obj.id]
      
      else obj
      end
    end
    
    # Commits the current tree to branch with the specified message.  The
    # branch is created if it doesn't already exist.
    def commit(message, options={})
      raise "no changes to commit" if status.empty?
      
      repo_path = "#{repo.path}/refs/heads/#{branch}"
      
      mode, tree_id = write_tree
      parent = self.current
      author = options[:author] || user
      authored_date = options[:authored_date] || Time.now
      committer = options[:committer] || author
      committed_date = options[:committed_date] || Time.now
      
      lines = []
      lines << "tree #{tree_id}"
      lines << "parent #{parent.id}" if parent
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
  
      id = write('commit', lines.join("\n"))
      File.open(repo_path, "w") {|io| io << id }
      @tree = self["/"]
      id
    end
    
    def status
      prune_tree.delete_if {|key, value| value.nil? }
    end
    
    def add(files)
      files.each_pair do |path, content|
        tree = @tree
        base = segments(path, true) do |seg|
          tree.delete(seg) unless tree[seg].kind_of?(Hash)
          tree = tree[seg]
        end
        
        entry = content.kind_of?(Array) ? content : ["100644", write("blob", content)]
        entry[2] = :add
        tree[base] = entry
      end
      
      self
    end
    
    def rm(*paths)
      paths.each do |path|
        tree = @tree
        segments(path) do |seg|
          tree.delete(seg) unless tree[seg].kind_of?(Hash)
          tree = tree[seg]
        end
        
        if tree.kind_of?(Array)
          tree[2] = :rm
        else
          recursive_paths = tree.keys.collect! {|key| File.join(path, key) }
          rm *recursive_paths
        end
      end
      
      self
    end
    
    # Write a raw object to the repository.
    #
    # Returns the object id.
    def write(type, content)
      data = "#{type} #{content.length}\0#{content}"    
      id = Digest::SHA1.hexdigest(data)[0, 40]
      path = "#{repo.path}/objects/#{id[0...2]}/#{id[2..39]}"

      unless File.exists?(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'wb') do |io|
          io.write Zlib::Deflate.deflate(data)
        end
      end

      id
    end
    
    protected
    
    def segments(path, return_last=false) # :nodoc:
      paths = path.split("/")
      last = return_last ? paths.pop : nil
      
      while seg = paths.shift
        next if seg.empty?
        yield(seg)
      end
      
      last
    end
    
    def write_tree(tree=@tree) # :nodoc:
      lines = tree.keys.sort!.collect! do |key|
        value = tree[key]
        value = write_tree(value) if value.kind_of?(Hash)
        
        mode, id = value
        "#{mode} #{key}\0#{[id].pack("H*")}"
      end
      
      ["040000", write("tree", lines.join("\n")), :add]
    end
    
    def prune_tree(tree=@tree) # :nodoc:
      hash = {}
      tree.each_pair do |key, value|
        if value.kind_of?(Hash)
          value = prune_tree(value)
        end
        
        next if value.nil?
        hash[key] = value.kind_of?(Hash) ? value : value[2]
      end
      
      hash.empty? ? nil : hash
    end
    
    def recursive_hash # :nodoc:
      Hash.new do |hash, key|
        default = block_given? ? yield(key) : nil
        hash[key] = default || recursive_hash
      end
    end
  end
end