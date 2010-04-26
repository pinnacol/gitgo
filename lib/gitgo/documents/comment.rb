require 'gitgo/document'

module Gitgo
  module Documents
    class Comment < Document
      define_attributes do
        attr_accessor(:content) {|content| validate_not_blank(content) }
        attr_accessor(:re)      {|re| validate_format_or_nil(re, SHA) }
      end
      
      def normalize!
        if re = attrs['re']
          attrs['re'] = repo.resolve(re)
        end
        
        super
      end
    end
  end
end