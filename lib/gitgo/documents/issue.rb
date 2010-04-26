require 'gitgo/document'

module Gitgo
  module Documents
    class Issue < Document
      class << self
        def find(all={}, any=nil, update_index=true)
          self.update_index if update_index
          repo.index.select(
            :basis => basis, 
            :all => all, 
            :any => any, 
            :shas => true,
            :map => true
          ).collect! {|sha| self[sha] }
        end
        
        protected
        
        def basis
          repo.index['type'][type] - repo.index['filter']['tail']
        end
      end
      
      define_attributes do
        attr_accessor(:title)
        attr_accessor(:content)
      end
      
      def graph_heads
        graph[graph_head].versions.collect {|head| Issue[head] or raise "missing head: #{head.inspect} (#{sha})" }
      end
      
      def graph_titles
        graph_heads.collect {|head| head.title }
      end
      
      def graph_states
        graph_tails.collect {|tail| tail.state }
      end
      
      def graph_tags
        graph_tails.collect {|tail| tail.tags }.flatten.uniq
      end
      
      def graph_active?(commit=nil)
        graph_tails.any? {|tail| tail.active?(commit) }
      end
      
      def graph_tails
        graph.tails.collect {|tail| Issue[tail] or raise "missing tail: #{tail.inspect} (#{sha})" }
      end
      
      def inherit(attrs={})
        attrs['tags'] ||= graph_tags
        self.class.new(attrs, repo)
      end
    end
  end
end