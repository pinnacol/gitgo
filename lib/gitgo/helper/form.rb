require 'rack/utils'

module Gitgo
  module Helper
    class Form
      include Rack::Utils
      
      DEFAULT_STATES = %w{open closed}
      
      attr_reader :controller
      
      def initialize(controller)
        @controller = controller
      end
      
      def url(*paths)
        controller.url(paths)
      end
      
      def refs
        @refs ||= controller.grit.refs.sort {|a, b| a.name <=> b.name }
      end
      
      def states
        @states ||= (DEFAULT_STATES + controller.idx.values("states")).uniq
      end
    
      def tags
        @tags ||= controller.idx.values("tags")
      end
      
      #
      #
      #
      
      def value(str)
        str
      end
      
      #
      # documents
      #
      
      def at(sha)
        return '(unknown)' unless sha
        
        refs = refs.select {|ref| ref.commit.sha == sha }
        refs.collect! {|ref| escape_html ref.name }
        
        ref_names = refs.empty? ? nil : " (#{refs.join(', ')})"
        "#{sha_a(sha)}#{ref_names}"
      end
      
      def author_value(author)
        escape_html(author)
      end
      
      def title_value(title)
        escape_html(title)
      end
      
      def tags_value(tags)
        tags.join(', ')
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
        tags.sort.each do |tag|
          yield escape_html(tag), selected.include?(tag), escape_html(tag)
        end
      end
      
      def each_ref(selected_name) # :yields: value, select_or_check, content
        refs.each do |ref|
          yield escape_html(ref.commit), selected_name == ref.name, escape_html(ref.name)
        end
      end
      
      def each_ref_name(selected_name) # :yields: value, select_or_check, content
        found_selected_name = false
        
        refs.each do |ref|
          select_or_check = selected_name == ref.name
          found_selected_name = true if select_or_check
          
          yield escape_html(ref.name), select_or_check, escape_html(ref.name)
        end
        
        if found_selected_name
          yield("", false, "(none)")
        else
          yield(selected_name, true, selected_name.to_s.empty? ? "(none)" : selected_name)
        end
      end
      
      def each_remote_name(selected_name, include_none=true) # :yields: value, select_or_check, content
        found_selected_name = false
        refs.each do |ref|
          next unless ref.kind_of?(Grit::Remote)
          
          select_or_check = selected_name == ref.name
          found_selected_name = true if select_or_check
          
          yield escape_html(ref.name), select_or_check, escape_html(ref.name)
        end
        
        if found_selected_name
          yield("", false, "(none)")
        else
          yield(selected_name, true, selected_name.to_s.empty? ? "(none)" : selected_name)
        end
      end
    end
  end
end