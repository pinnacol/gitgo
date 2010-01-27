require 'rack/utils'

module Gitgo
  module Helpers
    class Form
      include Rack::Utils
      
      DEFAULT_STATES = %w{open closed}
      
      attr_reader :controller
      
      def initialize(controller)
        @controller = controller
      end
      
      def url(*paths)
        controller.url(*paths)
      end
      
      def refs
        controller.refs
      end
      
      def states
        @states ||= (DEFAULT_STATES + controller.repo.index.values("states")).uniq
      end
    
      def tags
        @tags ||= controller.repo.index.values("tags")
      end
      
      #
      #
      #
      
      def check(true_or_false)
        true_or_false ? ' checked="checked"' : nil
      end

      def select(true_or_false)
        true_or_false ? ' selected="selected"' : nil
      end
      
      #
      #
      #
      
      def title_value(title)
        escape_html(title)
      end
      
      def tags_value(tags)
        tags ? tags.collect {|tag| "'#{tag}'" }.join(' ') : ''
      end
      
      def content_value(content)
        content
      end
      
      def each_state(*current) # :yields: value, select_or_check, content
        states.each do |state|
          yield escape_html(state), current.include?(state), escape_html(state)
        end
      end
      
      def each_tag(*current) # :yields: value, select_or_check, content
        tags.each do |tag|
          yield escape_html(tag), current.include?(tag), escape_html(tag)
        end
      end
      
      def each_ref(*current) # :yields: value, select_or_check, content
        refs.each do |ref|
          yield escape_html(ref.commit), current.include?(ref.commit.sha), escape_html(ref.name)
        end
        yield '', false, '(none)'
      end
    end
  end
end