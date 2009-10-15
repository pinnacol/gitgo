require 'zlib'
require 'digest/sha1'
require 'fileutils'
require 'grit'

module Gitgo
  class Repo
    # The internal Grit::Repo
    attr_reader :repo
    
    # The internal GitStore
    attr_reader :store
    
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
    
    # Write a raw object to the repository.
    #
    # Returns the object id.
    def set(type, content)
      data = "#{type} #{content.length}\0#{content}"    
      id = Digest::SHA1.hexdigest(data)[0, 40]
      path = "#{repo.path}/objects/#{id[0...2]}/#{id[2..39]}"

      unless File.exists?(path)
        FileUtils.mkpath(File.dirname(path))
        open(path, 'wb') do |f|
          f.write Zlib::Deflate.deflate(data)
        end
      end

      id
    end
    
    def commit(message, options={})
      author = options[:author] || user
      authored_date = options[:authored_date] || Time.now
      committer = options[:committer] || author
      committed_date = options[:committed_date] || Time.now
      
      mode, tree_id = set_tree
      
      lines = []
      lines << "tree #{tree_id}"
      lines << "parent #{current.id}"
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
      
      id = set('commit', lines.join("\n"))
      File.open("#{repo.path}/refs/heads/#{branch}", "w") {|io| io << id }
      @tree = self["/"]
      id
    end
    
    def add(files)
      files.each_pair do |path, content|
        tree = @tree
        base = segments(path, true) do |seg|
          tree.delete(seg) unless tree[seg].kind_of?(Hash)
          tree = tree[seg]
        end
        
        unless content.kind_of?(Array)
          content = ["100644", set("blob", content)]
        end
        
        tree[base] = content
      end
      
      self
    end
    
    protected
    
    # returns the current commit
    def current # :nodoc:
      repo.commits(branch, 1).first or raise "invalid branch: #{branch}"
    end
    
    def segments(path, return_last=false)
      paths = path.split("/")
      last = return_last ? paths.pop : nil
      
      while seg = paths.shift
        next if seg.empty?
        yield(seg)
      end
      
      last
    end
    
    # note this is destructive to the tree
    def set_tree(tree=@tree) # :nodoc:
      lines = tree.keys.sort!.collect! do |key|
        value = tree[key]
        value = set_tree(value) if value.kind_of?(Hash)
        "#{value.shift} #{key}\0#{value.pack("H*")}"
      end
      
      ["040000", set("tree", lines.join("\n"))]
    end
    
    def recursive_hash
      Hash.new do |hash, key|
        default = block_given? ? yield(key) : nil
        hash[key] = default || recursive_hash
      end
    end
  end
end