require 'gitgo/repo/node'

module Gitgo
  class Repo
    # Graph performs the important and somewhat complicated task of
    # deconvoluting document graphs.  Graph and Node use signifant amounts of
    # caching to make sure traversal of the document graph is as quick as
    # possible.  Graphs must be reset to detect any associations added after
    # initialization.
    #
    # See Gitgo::Repo for terminology used in this documentation.
    #
    # == Deconvolution
    #
    # Deconvolution involves replacing each node in a DAG with the current
    # versions of that node, and specifically reassigning parent and children
    # links from updated nodes to their current versions.
    #
    #          a                              a
    #          |                              |
    #          b -> b1                        b1--+
    #          |    |                         |   |
    #          c    |             becomes     c   |
    #               |                             |
    #               d                             d
    #
    # When multiple current versions exist for a node, a new fork in the graph
    # is introduced:
    #
    #          a                              a
    #          |                              |--+
    #          b -> [b1, b2]                  b1 |
    #          |                              |  |
    #          c                 becomes      |  b2
    #                                         |  |
    #                                         c--+
    #
    # These forks can happen anywhere (including the graph head), as can
    # updates that merge multiple revisions:
    #
    #          a                              a
    #          |                              |
    #          b -> [b1, b2] -> b3            b3
    #          |                              |
    #          c                 becomes      c
    #
    # Linkages for the convoluted graph is not directly available from Graph,
    # although all nodes are (via nodes).
    #
    # == Notes
    #
    # The possibility of multiple current versions is perhaps non-intuitive,
    # but entirely possible if user A modifies a document while separately
    # user B modifies the same document in a different way.  When these
    # changes are merged, you end up with multiple current versions.
    #
    class Graph
      include Enumerable
      
      # A back-reference to the repo where the documents are stored
      attr_reader :repo
      
      # The graph head
      attr_reader :head
      
      # A hash of (sha, node) pairs identifying all accessible nodes
      attr_reader :nodes
      
      # Creates a new Graph
      def initialize(repo, head)
        @repo = repo
        @head = head
        reset
      end
      
      # Returns true if head is nil (implying that no meaningful nodes can be
      # reached from this graph).
      def empty?
        head.nil?
      end
      
      # Same as node.
      def [](sha)
        nodes[sha]
      end
      
      # Retrieves the node for the sha, or nil if the node is inaccessible
      # from this document graph.
      def node(sha)
        nodes[sha]
      end
      
      # Returns a hash of (node, children) pairs mapping linkages in the
      # deconvoluted graph.  Links does not contain updated or deleted nodes
      # and typically serves as the basis for drawing graphs.
      def links
        @links ||= begin
          links = {}
          unless head.nil?
            versions = nodes[nodes[head].original].versions
            versions.each {|sha| collect_links(sha, links) }
            
            links[nil] = versions
          end
          links
        end
      end
      
      # Returns an array the tail nodes in the deconvoluted graph.
      def tails
        @tails ||= begin
          tails = []
          links.each_pair do |node, children|
            tails << node if children.empty?
          end
          tails
        end
      end
      
      # Sorts each of the children in links, using the block if given.
      def sort(&block)
        links.each_value do |children|
          children.sort!(&block)
        end
        self
      end
      
      # Yields each node in the deconvoluted graph to the block with
      # coordinates for rendering linkages between the nodes. The nodes are
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
        
        # visit walks each branch in the DAG and collects the visited nodes
        # in reverse; that way uniq + reverse_each will iterate the nodes in
        # order, with merges pushed down as far as necessary
        order = visit(links, head)
        order.uniq!
        
        index = 0
        order.reverse_each do |sha|
          children = links[sha]
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
      
      # Draws the graph
      def draw(indent=0)
        lines = []
        each do |(sha, slot, index, current_slots, transitions)|
          next if sha.nil?
          
          line = []
          transition = []
          
          transitions.each do |target|
            tstart = (slot * 2) + indent
            tend = (target * 2) + indent
            
            if tstart > tend
              tstart, tend = tend, tstart
            end
            
            tstart.upto(tend) {|i| transition[i] = '-'}
            transition[tstart] = '+'
            transition[tend] = '+'
          end
          
          if transitions.include?(slot)
            transition[(slot * 2) + indent] = '|'
          end
          
          current_slots.each do |cs|
            line[(cs * 2) + indent] = '|'
            transition[(cs * 2) + indent] = '|'
          end
          
          line[(slot * 2) + indent] = '*'
          
          lines << line.collect! {|obj| obj.nil? ? ' ' : obj }.join
          lines << transition.collect! {|obj| obj.nil? ? ' ' : obj }.join
        end
        
        lines.join("\n")
      end
      
      # Resets the graph, recollecting all nodes and links.  Reset is required
      # detect new nodes inserted after initialization.
      #
      #-- 
      #
      # Nodes are collected in an ambigous order by collect_nodes.  As a
      # result is not feasible to determine the relationships of previous and
      # updated nodes in one pass. First collects all nodes, then deconvolute
      # original nodes.  Updates do not have to be deconvoluted directly
      # because they will be deconvoluted from their original (indeed it will
      # cause duplicates in the graph tree if updates are deconvoluted
      # separately).
      #
      def reset
        @nodes = {}
        collect_nodes(head)
        
        nodes.each_value do |node|
          if node.original?
            node.deconvolute
          end
        end
        
        @links = nil
        self
      end
      
      # Returns a string like:
      #
      #   #<Gitgo::Repo::Graph:object_id head="sha">
      #
      def inspect
        "#<#{self.class}:#{object_id} head=#{head.inspect}>"
      end
      
      protected
      
      # helper method to recursively collect all nodes in the graph, with the
      # raw linkage information.  after nodes are collected they must be
      # deconvoluted.
      def collect_nodes(sha) # :nodoc:
        node = nodes[sha]
        return node if node
        
        links = []
        updates = []
        
        node = Node.new(sha, nodes, links, updates)
        nodes[sha] = node
        
        repo.each_assoc(sha) do |doc_sha, doc_type|
          target = collect_nodes(doc_sha)
          
          case doc_type
          when :head
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
      
      # helper method to recursively collect node linkages. collect_links
      # walks each current trail in the nodes and is designed to fail if
      # circular linkages are detected.
      def collect_links(sha, links, trail=[]) # :nodoc:
        circular = trail.include?(sha)
        trail.push sha

        if circular
          raise "circular link detected:\n  #{trail.join("\n  ")}\n"
        end

        links[sha] ||= begin
          nodes[sha].children.each do |child|
            collect_links(child, links, trail)
          end
        end

        trail.pop
      end
      
      # helper method to walk the DAG and collect each visited node in
      # reverse -- afterwards the unique, reversed array represents the
      # graphing order for the nodes.
      def visit(links, parent, visited=[]) # :nodoc:
        visited.unshift(parent)
        links[parent].each do |child|
          visit(links, child, visited)
        end
        visited
      end
    end
  end
end