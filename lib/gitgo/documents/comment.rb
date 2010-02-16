require 'gitgo/document'

module Gitgo
  module Documents
    class Comment < Document
      define_attributes do
        attr_accessor(:content) {|content| validate_not_blank(content) }
      end
      
      def validate_re(re)
        raise 'no re specified' if re.nil?
        super
      end
    end
  end
end