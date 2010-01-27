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
      
      def states
        @states ||= (DEFAULT_STATES + controller.repo.index.values("states")).uniq
      end
    
      def tags
        @tags ||= controller.repo.index.values("tags")
      end
      
      #
      #
      #
      
      def value(str)
        str
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
      
      def each_state(*selected) # :yields: value, select_or_check, content
        states.each do |state|
          yield escape_html(state), selected.include?(state), escape_html(state)
        end
      end
      
      def each_tag(*selected) # :yields: value, select_or_check, content
        tags.each do |tag|
          yield escape_html(tag), selected.include?(tag), escape_html(tag)
        end
      end
      
      def each_ref(selected_name) # :yields: value, select_or_check, content
        controller.refs.each do |ref|
          yield escape_html(ref.commit), selected_name == ref.name, escape_html(ref.name)
        end
      end
      
      def each_ref_name(selected_name) # :yields: value, select_or_check, content
        controller.refs.each do |ref|
          yield escape_html(ref.name), selected_name == ref.name, escape_html(ref.name)
        end
      end
      
      def each_remote_name(selected_name) # :yields: value, select_or_check, content
        controller.refs.each do |ref|
          next unless ref.kind_of?(Grit::Remote)
          yield escape_html(ref.name), selected_name == ref.name, escape_html(ref.name)
        end
      end
    end
  end
end