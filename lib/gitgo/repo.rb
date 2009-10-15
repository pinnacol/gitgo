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
    
    def initialize(path=".", options={})
      @repo = Grit::Repo.new(path, options)
      self.branch = options[:branch] || 'gitgo'
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
    
    # Returns the commit for branch.  Raises an error if no commit can
    # be found for the branch.
    def commit
      repo.commits(branch, 1).first or raise "invalid branch: #{branch}"
    end
    
    # Gets the object at the specified path
    def get(path)
      current = commit.tree
      
      paths = path.split("/")
      while seg = paths.shift
        next if seg.empty?
        return nil unless current.respond_to?(:/)
        current = current / seg
      end
      
      current
    end
    
    def put(path, content)
      store[path] = content
    end
  end
end