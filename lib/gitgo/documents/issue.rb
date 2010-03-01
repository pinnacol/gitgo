require 'gitgo/document'

module Gitgo
  module Documents
    class Issue < Document
      define_attributes do
        attr_accessor(:title) {|title| validate_not_blank(title) }
        attr_accessor(:content)
        attr_accessor(:state)
      end
    end
  end
end