require 'grit'

module Gitgo
  class Repo
    
    # The internal Grit::Repo
    attr_reader :repo
    
    # The active branch/commit name
    attr_accessor :branch
    
    def initialize(path=".", options={})
      @repo = Grit::Repo.new(path, options)
      @branch = options[:branch] || 'gitgo'
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
  end
end