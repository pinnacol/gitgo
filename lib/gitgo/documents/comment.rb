require 'gitgo/document'

module Gitgo
  module Documents
    class Comment < Document
      define_attributes do
        attr_accessor(:content) {|content| validate_not_blank(content) }
      end
      
      def validate_origin(origin)
        raise 'missing' if origin.nil?
        super
      end
    end
  end
end