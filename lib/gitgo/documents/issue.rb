require 'gitgo/document'

module Gitgo
  module Documents
    class Issue < Document
      class << self
        def find(all={}, any=nil, update_index=true)
          self.update_index if update_index
          index.select(
            :basis => basis, 
            :all => all, 
            :any => any, 
            :shas => true,
            :map => true
          ).collect! {|sha| self[sha] }
        end
        
        protected
        
        def basis
          index['type'][type] - index['filter']['tail']
        end
      end
      
      define_attributes do
        attr_accessor(:title)
        attr_accessor(:state)   {|state| validate_not_blank(state) }
        attr_accessor(:content)
      end
      
      def graph_heads
        graph[graph_head].versions.collect {|sha| Issue[sha] }
      end
      
      def graph_tails
        graph.tails.collect {|tail| Issue[tail] }
      end
      
      def each_index
        if state = attrs['state']
          yield('state', state)
        end
        
        super
      end
    end
  end
end