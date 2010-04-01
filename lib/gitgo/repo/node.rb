module Gitgo
  class Repo
    class Node
      attr_reader :sha
      attr_reader :nodes
      
      attr_accessor :deleted
      attr_accessor :original
      
      def initialize(sha, nodes, links, updates)
        @sha = sha
        @links = links
        @updates = updates
        @nodes = nodes
        
        @deleted = false
        @original = sha
      end
      
      def original?
        original == sha
      end
      
      def current?
        !deleted && @updates.empty?
      end
      
      def tail?
        current? && @links.empty?
      end
      
      def parents
        @parents ||= begin
          parents = []
          
          nodes.each_value do |node|
            if node.children.include?(sha)
              parents << node.sha
            end
          end if current?
          
          parents
        end
      end
      
      def children
        @children ||= begin
          children = []
          
          @links.each do |link|
            children.concat nodes[link.original].versions
          end if current?
          
          children
        end
      end
      
      def versions
        @versions ||= deconvolute(nil)
      end
      
      def deconvolute(original=sha, links=nil, versions=[])
        if original
          @original = original
          @links.concat(links) if links
          @versions = versions if original == sha
        end
        
        case
        when deleted
          # do nothing
        when @updates.empty?
          versions << sha
        else
          @updates.each do |update|
            update.deconvolute(original, @links, versions)
          end
        end
        
        versions
      end
      
      def inspect
        "#<#{self.class}:#{object_id} sha=#{sha}>"
      end
    end
  end
end