require 'gitgo/document'

module Gitgo
  module Documents
    class Issue < Document
      class << self
        def find(all={}, any=nil, update_idx=true)
          self.update_idx if update_idx
          
          idx = repo.idx
          shas = (all ? all.delete('shas') : nil) || basis
          shas = [shas] unless shas.kind_of?(Array)
          
          shas = idx.select(shas, all, any)
          shas.collect! {|sha| idx.map[sha] }
          shas.uniq!
          shas.collect! {|sha| self[sha] }
          shas
        end
        
        def basis
          idx.get('type', type) - idx.get('tail', 'filter')
        end
      end
      
      define_attributes do
        attr_accessor(:title)   {|title| !origin? || validate_not_blank(title) }
        attr_accessor(:state)   {|state| validate_not_blank(state) }
        attr_accessor(:content)
      end
      
      def heads
        graph.versions(origin).collect {|sha| Issue[sha] }
      end
      
      def tails
        graph.tails.collect {|tail| Issue[tail] }
      end
      
      def titles
        heads.collect! {|head| head.title }
      end
      
      def current_tags
        tags = []
        tails.each {|tail| tags.concat tail.tags }
        tags.uniq!
        tags
      end
      
      def current_states
        states = tails.collect {|tail| tail.state }
        states.uniq!
        states
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