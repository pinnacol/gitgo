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
      
      #
      # general formatters
      #
      
      def text(str)
        str = escape_html(str)
        str.gsub!(/[a-f0-9]{40}/) {|sha| sha_a(sha) }
        str
      end
      
      def sha(sha)
        escape_html(sha)
      end
      
      #
      # links
      #
      
      def sha_a(sha)
        "<a class=\"sha\" href=\"#{url('obj', sha)}\" title=\"#{sha}\">#{sha}</a>"
      end
      
      def issue_a(doc)
        title = doc['title']
        title = "(nameless issue)" if title.to_s.empty?
        state = doc['state']
        
        "<a class=\"#{escape_html state}\" id=\"#{doc.sha}\" active=\"#{doc[:active]}\" href=\"#{url('issue', doc.sha)}\">#{escape_html title}</a>"
      end
      
      def index_key_a(key)
        "<a href=\"#{url('repo', 'idx', key)}\">#{escape_html key}</a>"
      end
      
      def index_value_a(key, value)
        "<a href=\"#{url('repo', 'idx', key, value)}\">#{escape_html value}</a>"
      end
      
      #
      # documents
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
      
      def at(sha)
        return '(unknown)' unless sha
        
        refs = controller.refs.select {|ref| ref.commit.sha == sha }
        refs.collect! {|ref| escape_html ref.name }
        
        ref_names = refs.empty? ? nil : " (#{refs.join(', ')})"
        "#{sha_a(sha)}#{ref_names}"
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
      
      #
      # repo
      #
      
      def path(path)
        escape_html(path)
      end
      
      def branch(branch)
        escape_html(branch)
      end
    end
  end
end
      