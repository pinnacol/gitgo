require 'redcloth'
require 'rack/utils'

module Gitgo
  module Helpers
    include Rack::Utils
    
    # Returns a title for pages served from this controller; either the
    # capitalized resource name or the class basename.
    def title
      self.class.to_s.split("::").last.capitalize
    end
    
    def gformat(str)
      str = escape_html(str)
      str.gsub!(/[a-f0-9]{40}/) {|sha| sha_link(sha) }
      str
    end
    
    def tformat(str)
      ::RedCloth.new(gformat(str)).to_html
    end
    
    def checked?(true_or_false)
      true_or_false ? 'checked="true" ' : ''
    end
    
    def selected?(true_or_false)
      true_or_false ? 'selected="true" ' : ''
    end
    
    def render_comments(sha)
      comments = repo.comments(sha, cache)
       
      if comments.empty?
        erb(:_comment_form, :locals => {:sha => sha, :parent => nil}, :layout => false)
      else
        erb(:_comments, :locals => {:comments => comments}, :layout => false)
      end
    end
  end
end
