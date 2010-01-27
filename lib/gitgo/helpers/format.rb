require 'rack/utils'

module Gitgo
  module Helpers
    class Format
      include Rack::Utils
      
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
      
      def text(str)
        str = escape_html(str)
        str.gsub!(/[a-f0-9]{40}/) {|sha| self.sha(sha) }
        str
      end
      
      def sha(sha)
        "<a href=\"#{url('obj', sha)}\" title=\"#{escape_html(sha)}\">#{escape_html(sha[0,8])}</a>"
      end
      
      #
      #
      #
      
      # a document title
      def title(title)
        escape_html(title)
      end
      
      def content(str)
        ::RedCloth.new(text(str)).to_html
      end
      
      def author(author)
        "#{escape_html(author.name)} (<a href=\"#{url('timeline')}?#{build_query(:author => author.email)}\">#{escape_html author.email}</a>)"
      end
      
      def date(date)
        "<abbr title=\"#{date.iso8601}\">#{date.strftime('%Y/%m/%d %H:%M %p')}</abbr>"
      end
      
      def ref(sha)
        refs.find {|ref| ref.commit.sha == sha }
      end
      
      def at(sha)
        return '(unknown)' unless sha
        
        ref = self.ref(sha) 
        name = ref ? " (#{ref.name})" : nil
        "#{self.sha(sha)}#{name}"
      end
      
      def tags(tags)
        # add links/clouds
        escape_html tags.join(', ')
      end
      
      def state(state)
        escape_html state
      end
      
      def states(states)
        escape_html states.join(', ')
      end
    end
  end
end
      