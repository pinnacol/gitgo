module Gitgo
  class Repo
    
    # Nodes are used to cache and provide access to positional information
    # (parents, children, etc) for each node in a graph.  Nodes are meant to
    # be read-only objects and should not be modified.
    class Node
      
      # The node sha
      attr_reader :sha
      
      # A back reference to the graph nodes this node belongs to.
      attr_reader :nodes
      
      # True if self is deleted
      attr_accessor :deleted
      
      # Set to the sha for the original node this node updates, or the sha for
      # self if self is an original node.
      attr_accessor :original
      
      # Initializes a new Node.  The links and updates arrays represent raw
      # linkage information before deconvolution and are not made available
      # because they are changed in the course of deconvolution.
      def initialize(sha, nodes, links, updates)
        @sha = sha
        @nodes = nodes
        @links = links
        @updates = updates
        @deleted = false
        @original = sha
      end
      
      # True if self is an original node.
      def original?
        original == sha
      end
      
      # True if self is a current version of a node (ie not deleted or
      # updated).
      def current?
        !deleted && @updates.empty?
      end
      
      # True if self is a tail (ie current and without children)
      def tail?
        current? && @links.empty?
      end
      
      # Returns an array of deconvoluted parent for self.
      def parents
        @parents ||= begin
          parents = []
          
          nodes.each_value do |node|
            if node.current? && node.children.include?(sha)
              parents << node.sha
            end
          end if current?
          
          parents
        end
      end
      
      # Returns an array of deconvoluted children for self.
      def children
        @children ||= begin
          children = []
          
          @links.each do |link|
            children.concat nodes[link.original].versions
          end if current?
          
          children
        end
      end
      
      # Returns an array of current versions for self.
      def versions
        @versions ||= deconvolute(nil)
      end
      
      # Deconvolute is a utility method used by a graph to:
      #
      # * aggregate links from previous versions to updates
      # * determine the current versions for an original node
      # * determine the original node for each update
      #
      # This method is public so that it may be used from a Graph, but should
      # not be called otherwise.
      #--
      # Deconvolution is necessary because, due to the arbitrary order in
      # which nodes are initially collected into a graph, it is not feasible
      # to immediately and unambiguously determine the relationships of
      # previous and updated nodes.  For that, all of the nodes within a graph
      # must be available.
      #
      # Internally Graph first collects all nodes, then deconvolutes all
      # original nodes.  Updates do not have to be deconvoluted directly
      # because they will be deconvoluted from their original (indeed it can
      # cause duplicates in the graph tree if updates are deconvoluted
      # separately).
      #
      def deconvolute(original=sha, links=nil, versions=[])
        if original
          @original = original
          @links.concat(links) if links
          @versions = versions if original == sha
        end
        
        case
        when deleted
          # do not register deleted notes as current
          # so that they will fall out of the tree
        when @updates.empty?
          versions << sha
        else
          @updates.each do |update|
            update.deconvolute(original, @links, versions)
          end
        end
        
        versions
      end
      
      # Returns a string like:
      #
      #   #<Gitgo::Repo::Node:object_id sha="sha">
      #
      def inspect
        "#<#{self.class}:#{object_id} sha=#{sha.inspect}>"
      end
    end
  end
end