module Gitgo
  class Repo
    class Graph
    
      attr_reader :repo
      attr_reader :head
    
      def initialize(repo, head)
        @repo = repo
        @head = head
        reset
      end
    
      def versions(sha)
        @versions[sha] ||= collect_versions(sha)
      end
    
      def children(sha)
        tree[sha]
      end
    
      def tree
        @tree ||= begin
          tree = {}
          tree[nil] = collect_tree(head, tree)
          tree
        end
      end
    
      def reset
        @links = {}
        @updates = {}
        @versions = {}
        @tree = nil
      end
    
      protected 
    
      def links(sha) # :nodoc:
        @links[sha] || collect_links(sha, true)
      end
    
      def updates(sha) # :nodoc:
        @updates[sha] || collect_links(sha, false)
      end
    
      def collect_links(sha, return_links) # :nodoc:
        links = []
        updates = []
      
        repo.each_link(sha, true) do |link, update|
          case update
          when false then links << link
          when true  then updates << link
          else links.concat self.links(link)
          end
        end
      
        @links[sha] = links
        @updates[sha] = updates
      
        return_links ? links : updates
      end
    
      def collect_versions(sha, target=[]) # :nodoc:
        updates = self.updates(sha)
      
        updates.each do |update|
          collect_versions(update, target)
        end
      
        if updates.empty?
          target << sha
        end
      
        target
      end
    
      # Helper to recursively collect the nodes for a tree. Returns and array of
      # the versions nodes representing sha.
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
      # detected.  The tracking trails follow only the 'versions' shas, they will
      # not show the path through the updated shas.
      def collect_tree(sha, tree, trail=[]) # :nodoc:
        versions(sha).each do |node|
          circular = trail.include?(node)
          trail.push node

          if circular
            raise "circular link detected:\n  #{trail.join("\n  ")}\n"
          end
        
          nodes = []
          links(node).each do |child|
            nodes.concat collect_tree(child, tree, trail)
          end

          tree[node] = nodes
          trail.pop
        end
      end
    end
  end
end