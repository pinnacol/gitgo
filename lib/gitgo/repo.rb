require 'zlib'
require 'digest/sha1'
require 'fileutils'
require 'grit'
require 'git_store'

module Gitgo
  class Repo
    # The internal Grit::Repo
    attr_reader :repo
    
    # The internal GitStore
    attr_reader :store
    
    # The active branch/commit name
    attr_reader :branch
    
    # Sets the user.
    attr_writer :user
    
    def initialize(path=".", options={})
      @repo = Grit::Repo.new(path, options)
      self.branch = options[:branch] || 'gitgo'
      self.user = options[:user]
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
    
    # Sets the active branch/commit (note this also resets store).
    def branch=(branch)
      @branch = branch
      
      # git_store-0.3 does not support bare repositories; if the
      # repo looks bare (ie x.git), then use the parent directory
      path = repo.path
      path = File.dirname(path) if File.basename(path) == '.git' || File.extname(path) == '.git'
      @store = GitStore.new(path, branch)
      store.handler.clear
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
      
      lines = []
      lines << "tree #{store.root.write}"
      lines << "parent #{current.id}"
      lines << "author #{author.name} <#{author.email}> #{authored_date.strftime("%s %z")}"
      lines << "committer #{committer.name} <#{committer.email}> #{committed_date.strftime("%s %z")}"
      lines << ""
      lines << message
      
      id = set('commit', lines.join("\n"))
      File.open("#{repo.path}/refs/heads/#{branch}", "w") {|io| io << id }
      id
    end
    
    def add(path, content)
      store[path] = content
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
  end
end