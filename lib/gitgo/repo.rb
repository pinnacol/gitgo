require 'grit'

module Gitgo
  
  # A wrapper to a Grit::Repo that allows access and modification of
  # repository data by path, without checking the repository out.  The api is
  # patterned after commands you'd invoke on the command line.
  #
  # === Usage
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
  class Repo
    # The internal Grit::Repo
    attr_reader :repo
    
    # The active branch/commit name
    attr_accessor :branch
    
    # Sets the user.
    attr_writer :user
    
    attr_reader :tree
    
    def initialize(path=".", options={})
      @repo = Grit::Repo.new(path, options)
      @branch = options[:branch] || 'gitgo'
      @user = options[:user]
      
      @tree = self["/"]
    end
    
    # Returns the current commit for branch.  Raises an error if branch
    # doesn't point to a commit.
    def current
      repo.commits(branch, 1).first or raise "invalid branch: #{branch}"
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
      current = self.current.tree
      
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
        obj.data
        
      else obj
      end
    end
    
    def commit(message, options={})
      repo_path = "#{repo.path}/refs/heads/#{branch}"
      unless File.exists?(repo_path)
        raise "cannot commit unless on an existing, local branch"
      end
      
      lock = "#{repo_path}.lock"
      file = File.open(lock, "w")
      file.flock(File::LOCK_EX)
      Thread.current['gitgo_lock'] = file
      
      mode, tree_id = write_tree
      author = options[:author] || user
      authored_date = options[:authored_date] || Time.now
      committer = options[:committer] || author
      committed_date = options[:committed_date] || Time.now
    
      lines = []
      lines << "tree #{tree_id}"
      lines << "parent #{current.id}"
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
    
      id = write('commit', lines.join("\n"))
      File.open(repo_path, "w") {|io| io << id }
      @tree = self["/"]
      id
      
    ensure
      if file = Thread.current['gitgo_lock']
        file.close if file.respond_to?(:close)
        Thread.current['gitgo_lock'] = nil
      end
      
      File.unlink(lock) if File.exists?(lock)
    end
    
    def add(files)
      files.each_pair do |path, content|
        tree = @tree
        base = segments(path, true) do |seg|
          tree.delete(seg) unless tree[seg].kind_of?(Hash)
          tree = tree[seg]
        end
        
        unless content.kind_of?(Array)
          content = ["100644", write("blob", content)]
        end
        
        tree[base] = content
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
        FileUtils.mkpath(File.dirname(path))
        File.open(path, 'wb') do |f|
          f.write Zlib::Deflate.deflate(data)
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
    
    # note this is destructive to the tree
    def write_tree(tree=@tree) # :nodoc:
      lines = tree.keys.sort!.collect! do |key|
        value = tree[key]
        value = write_tree(value) if value.kind_of?(Hash)
        "#{value.shift} #{key}\0#{value.pack("H*")}"
      end
      
      ["040000", write("tree", lines.join("\n"))]
    end
    
    def recursive_hash # :nodoc:
      Hash.new do |hash, key|
        default = block_given? ? yield(key) : nil
        hash[key] = default || recursive_hash
      end
    end
  end
end