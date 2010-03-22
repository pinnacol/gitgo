module Gitgo
  class Repo
    class Graph
      include Enumerable
      
      attr_reader :repo
      attr_reader :head
    
      def initialize(repo, head)
        @repo = repo
        @head = head
        reset
      end
    
      def original(sha)
        @original[sha] || collect_links(sha, :original)
      end
    
      def versions(sha)
        @versions[sha] ||= collect_versions(sha)
      end
      
      # Returns parents of the indicated node.  Parents are deconvoluted so
      # that only the current version of a node will have parents. Detached
      # nodes will return no parents.
      def parents(sha)
        tree.keys.select do |key|
          current?(key) && tree[key].include?(sha)
        end
      end
      
      # Returns children of the indicated node.  Children are deconvoluted so
      # that only the current version of a node will have children.  Detached
      # nodes will return no children.
      def children(sha)
        tree[sha] || []
      end
      
      def tails
        @tails ||= begin
          tails = []
          tree.each_pair do |key, value|
            tails << key if value.empty?
          end
          tails
        end
      end
      
      def current?(sha)
        sha ? updates(sha).empty? : false
      end
      
      def tail?(sha)
        current?(sha) && links(sha).empty?
      end
    
      def tree
        @tree ||= begin
          tree = {}
          unless head.nil?
            tree[nil] = collect_tree(head, tree)
          end
          tree
        end
      end
      
      def sort(&block)
        tree.each_value do |children|
          children.sort!(&block)
        end
        self
      end
      
      def each(head=nil)
        slots = []
        slot = {head => 0}
        
        order = visit(tree, head)
        order.uniq!
        
        order.reverse_each do |sha|
          children = tree[sha]
          parent_slot  = slot[sha]
          
          # free the parent slot if possible
          slots[parent_slot] = children.empty? ? false : nil
          
          # determine occupied slots
          occupied_slots = slots.select {|index| index }
          
          # determine the slot for each child
          child_slots = children.collect do |child|
            child_slot = slot[child] ||= (slots.index(nil) || slots.length)
            slots[child_slot] = child_slot >= parent_slot ? child_slot : nil
            child_slot
          end
          
          yield(sha, slot[sha], occupied_slots, child_slots)
        end
        
        self
      end
      
      def reset
        @links = {}
        @updates = {}
        @original = {}
        @versions = {}
        @tree = nil
        @tails = nil
      end
    
      protected 
    
      def links(sha) # :nodoc:
        @links[sha] || collect_links(sha, :links)
      end
    
      def updates(sha) # :nodoc:
        @updates[sha] || collect_links(sha, :updates)
      end
    
      def collect_links(sha, return_type) # :nodoc:
        links = []
        updates = []
        original = sha
        
        repo.each_link(sha, true) do |link, update|
          case update
          when false then links << link
          when true  then updates << link
          else 
            links.concat self.links(link)
            original = @original[link]
          end
        end
        
        @links[sha] = links
        @updates[sha] = updates
        @original[sha] = original
      
        case return_type
        when :links    then links
        when :updates  then updates
        when :original then original
        else nil
        end
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
          collect_nodes(node, tree, trail)
        end
      end
      
      def collect_nodes(node, tree, trail=[]) # :nodoc:
        circular = trail.include?(node)
        trail.push node

        if circular
          raise "circular link detected:\n  #{trail.join("\n  ")}\n"
        end
        
        tree[node] ||= begin
          nodes = []
          links(node).each do |child|
            nodes.concat collect_tree(child, tree, trail)
          end
          nodes
        end
        
        trail.pop
      end
      
      def visit(tree, parent, visited=[]) # :nodoc:
        visited.unshift(parent)
        tree[parent].each do |child|
          visit(tree, child, visited)
        end
        visited
      end
    end
  end
end