require 'gitgo/repo/node'

module Gitgo
  class Repo
    # Graph performs the important and complicated task of creating and
    # providing access to document graphs.  Graph uses signifant amounts of
    # caching to make sure traversal of the document graph is quick.
    class Graph
      include Enumerable
      
      # A back-reference to the repo where the documents are stored
      attr_reader :repo
      
      # The document graph origin.
      attr_reader :head
      
      attr_reader :nodes
      
      def initialize(repo, head)
        @repo = repo
        @head = head
        reset
      end
      
      def [](sha)
        nodes[sha]
      end
      
      def tree
        @tree ||= begin
          tree= {}
          unless head.nil?
            versions = nodes[nodes[head].original].versions
            versions.each {|sha| collect_tree(sha, tree) }
            
            tree[nil] = versions
          end
          tree
        end
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
      
      # Sorts each of the children in tree, using the block if given.
      def sort(&block)
        tree.each_value do |children|
          children.sort!(&block)
        end
        self
      end
      
      # Yields each node in the tree to the block with coordinates for
      # rendering a graph of relationships between the nodes.  The nodes are
      # ordered from head to tails and respect the order of children.
      #
      # Each node is assigned a slot (x), and at each iteration (y), there is
      # information regarding which slots are currently open, and which slots
      # need to be linked to produce the graph.  For example, a simple
      # fork-merge could be graphed like this:
      #
      #   Graph    node  x  y  current transistions
      #   *        :a    0  0  []      [0,1]
      #   |--+
      #   *  |     :b    0  1  [1]     [0]
      #   |  |
      #   |  *     :c    1  2  [0]     [0]
      #   |--+
      #   *        :d    0  3  []      []
      #
      # Where the coordinates are the arguments yielded to the block:
      #
      #   sha::   the sha for the node
      #   slot::  the slot where the node belongs (x-axis)
      #   index:: a counter for the number of nodes yielded (y-axis)
      #   current_slots:: slots currently open (|)
      #   transitions:: the slots that this node should connect to (|,--+)
      #
      def each(head=nil) # :yields: sha, slot, index, current_slots, transitions
        slots = []
        slot = {head => 0}
        
        # visit walks each branch in the tree and collects the visited nodes
        # in reverse; that way uniq + reverse_each will iterate the nodes in
        # order, with merges pushed down as far as necessary
        order = visit(tree, head)
        order.uniq!
        
        index = 0
        order.reverse_each do |sha|
          children = tree[sha]
          parent_slot  = slot[sha]
          
          # free the parent slot if possible - if no children exist then the
          # sha is an open tail; keep these slots occupied
          slots[parent_slot] = nil unless children.empty?
          
          # determine currently occupied slots - any slots with a non-nil,
          # non-false value; in this case a number
          current_slots = slots.select {|s| s }
          
          transitions = children.collect do |child|
            # determine the next open (ie nil) slot for the child and occupy
            child_slot = slot[child] ||= (slots.index(nil) || slots.length)
            slots[child_slot] = child_slot
            child_slot
          end
          
          yield(sha, slot[sha], index, current_slots, transitions)
          index += 1
        end
        
        self
      end
      
      def reset
        @nodes = {}
        collect_nodes(head)
        
        nodes.each_value do |node|
          if node.original?
            node.deconvolute
          end
        end
        
        @tree = nil
        self
      end
      
      protected
      
      def collect_nodes(sha) 
        node = nodes[sha]
        return node if node
        
        links = []
        updates = []
        
        node = Node.new(sha, nodes, links, updates)
        nodes[sha] = node
        
        repo.each_linkage(sha) do |linkage, type|
          target = collect_nodes(linkage)
          
          case type
          when :link
            links   << target
          when :update
            updates << target
            target.original = nil
          when :delete
            target.deleted = true
          else
            raise "invalid linkage: #{sha} -> #{linkage}"
          end
        end
        
        node
      end
      
      def collect_tree(sha, tree, trail=[]) # :nodoc:
        circular = trail.include?(sha)
        trail.push sha

        if circular
          raise "circular link detected:\n  #{trail.join("\n  ")}\n"
        end

        tree[sha] ||= begin
          nodes[sha].children.each do |child|
            collect_tree(child, tree, trail)
          end
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