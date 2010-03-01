require 'gitgo/document'

module Gitgo
  module Documents
    class Update < Document
      define_attributes do
        attr_accessor(:content)
      end
    end
  end
end