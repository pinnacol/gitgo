module Gitgo
  module Helpers
    module Html
      module_function
      
      def check(true_or_false)
        true_or_false ? ' checked="checked"' : nil
      end

      def select(true_or_false)
        true_or_false ? ' selected="selected"' : nil
      end
      
      def disable(true_or_false)
        true_or_false ? ' disabled="disabled"' : nil
      end
    end
  end
end