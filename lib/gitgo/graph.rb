require 'gitgo/repo'

module Gitgo
  class Graph
    
    attr_reader :repo
    
    def initialize(repo)
      @repo = repo
      clear
    end
    
    def tree(sha, clear=false)
      tree = {}
      tree[nil] = collect_nodes(sha, tree)
      
      self.clear if clear
      tree
    end
    
    def clear
      @links = {}
      @updates = {}
      @previous = {}
      @current = {}
      @children = {}
    end
    
    protected 
    
    def links(sha)
      @links[sha] || collect_links(sha, 0)
    end
    
    def updates(sha)
      @updates[sha] || collect_links(sha, 1)
    end
    
    def previous(sha)
      @previous[sha] || collect_links(sha, 2)
    end
    
    def current(sha)
      @current[sha] ||= collect_current(sha)
    end
    
    def children(sha)
      @children[sha] ||= collect_children(sha)
    end
    
    def update?(sha)
      previous(sha) ? true : false
    end
    
    def collect_links(sha, index)
      links = []
      updates = []
      previous = nil
      
      repo.each_link(sha, true) do |link, update|
        case update
        when false then links << link
        when true  then updates << link
        else previous = link
        end
      end
      
      @links[sha] = links
      @updates[sha] = updates
      @previous[sha] = previous
      
      case index
      when 0 then links
      when 1 then updates
      when 2 then previous
      end
    end
    
    def collect_current(sha, target=[])
      updates = self.updates(sha)
      
      updates.each do |update|
        collect_current(update, target)
      end
      
      if updates.empty?
        target << sha
      end
      
      target
    end
    
    def collect_children(sha, target=[])
      if sha
        collect_children(previous(sha), target)
        target.concat links(sha)
      end
      
      target
    end
    
    # Helper to recursively collect the nodes for a tree. Returns and array of
    # the current nodes representing sha.
    #
    #   update(a, b)
    #   update(a, c)
    #   update(c, d)
    #   collect_nodes(a)  # => [b, d]
    #
    # The _nodes and _children caches were shown by benchmarking to
    # significantly speed up collection of complex graphs, while minimally
    # impacting simple graphs.
    #
    # This method is designed to detect and blow up when circular linkages are
    # detected.  The tracking trails follow only the 'current' shas, they will
    # not show the path through the updated shas.
    def collect_nodes(sha, tree, trail=[]) # :nodoc:
      current(sha).each do |node|
        circular = trail.include?(node)
        trail.push node

        if circular
          raise "circular link detected:\n  #{trail.join("\n  ")}\n"
        end
        
        nodes = []
        children(node).each do |child|
          nodes.concat collect_nodes(child, tree, trail)
        end

        tree[node] = nodes
        trail.pop
      end
    end
  end
end