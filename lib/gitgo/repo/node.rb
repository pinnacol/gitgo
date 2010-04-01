module Gitgo
  class Repo
    class Node
      attr_reader :sha
      attr_reader :links
      attr_reader :updates
      attr_reader :versions
      attr_accessor :deleted
      attr_accessor :original
      attr_reader :nodes
      
      def initialize(sha, links, updates, nodes)
        @sha = sha
        @links = links
        @updates = updates
        @nodes = nodes
        
        @deleted = false
        @original = self
        @versions = nil
      end
      
      def original?
        original == self
      end
      
      def current?
        !deleted && updates.empty?
      end
      
      def tail?
        current? && links.empty?
      end
      
      def deconvolute(original=self, versions=[])
        case
        when deleted
          # do nothing
        when updates.empty?
          versions << self
        else
          updates.each do |update|
            update.links.concat(links)
            update.deconvolute(original, versions)
          end
        end
        
        @original = original
        @versions = versions#.dup
      end
      
      def inspect
        "#<#{self.class}:#{object_id} sha=#{sha}>"
      end
    end
  end
end