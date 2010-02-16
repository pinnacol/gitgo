module Gitgo
  module Helpers
    class Doc
      
      attr_reader :controller
      
      def initialize(controller)
        @controller = controller
      end
      
      def url(*paths)
        controller.url(*paths)
      end
      
      def at
        controller.user_ref
      end
      
      def active_shas
        @active_shas ||= repo.rev_list(at)
      end
      
      def active?(sha)
        at && active_shas.include?(sha)
      end
    end
  end
end