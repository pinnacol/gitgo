require 'gitgo/document'

module Gitgo
  module Documents
    class Issue < Document
      class << self
        def find(criteria={}, update_idx=true)
          self.update_idx if update_idx
          
          idx = repo.idx
          shas = criteria.delete('shas') || basis
          shas = [shas] unless shas.kind_of?(Array)
          
          shas = idx.select(shas, criteria)
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
        attr_accessor(:content)
      end
      
      def tails
        graph.tails.collect {|tail| Issue[tail] }
      end
      
      def current_titles
        tails.collect! {|tail| tail.title }
      end
      
      def current_tags
        tags = []
        tails.each {|tail| tags.concat tail.tags }
        tags.flatten!
        tags.uniq!
        tags
      end
      
    end
  end
end