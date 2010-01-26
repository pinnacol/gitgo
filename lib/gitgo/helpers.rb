require 'redcloth'
require 'rack/utils'
require 'gitgo/constants'

module Gitgo
  module Helpers
    include Rack::Utils
    
    def mount_point
      @mount_point ||= (request.env[MOUNT] || '/')
    end
    
    def url(*paths)
      File.join(mount_point, *paths)
    end
    
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
    
    def format_date(date)
      "<abbr title=\"#{date.iso8601}\">#{date.strftime('%Y/%m/%d %H:%M %p')}</abbr>"
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
    
    #
    # link helpers
    #
    
    def commit_link(treeish)
      "<a href=\"#{url('commit', treeish)}\">#{escape_html(treeish)}</a>"
    end
    
    def path_link(type, treeish, *path_segments)
      "<a href=\"#{url(type, treeish, *path_segments)}\">#{escape_html(path_segments.pop || treeish)}</a>"
    end
    
    def full_path_link(type, treeish, *path_segments)
      path = File.join(*path_segments)
      "<a href=\"#{url(type, treeish, *path_segments)}\">#{escape_html(path)}</a>"
    end
    
    def tree_link(treeish, *path_segments)
      path_link('tree', treeish, *path_segments)
    end
    
    def blob_link(treeish, *path_segments)
      path_link('blob', treeish, *path_segments)
    end
    
    def obj_link(sha)
      "#{sha_link(sha)} (#{repo.type(sha)})"
    end

    def sha_link(sha)
      "<a href=\"#{url('obj', sha)}\">#{escape_html(sha)}</a>"
    end

    def show_link(obj)
      "<a href=\"#{url('obj', obj.id)}\">#{escape_html(obj.name)}</a>"
    end

    def activity_link(author)
      "#{escape_html(author.name)} (<a href=\"#{url('timeline')}?#{build_query(:author => author.email)}\">#{escape_html author.email}</a>)"
    end

    def commits_link(ref)
      "<a href=\"#{url('commits', ref)}\">history</a>"
    end

    def issue_link(doc)
      title = doc['title']
      title = "(nameless issue)" if title.to_s.empty?
      "<a class=\"#{escape_html doc['state']}\" href=\"#{url('issue', doc.sha)}\">#{escape_html title}</a>"
    end

    def path_links(treeish, path)
      paths = path.split("/")
      base = paths.pop
      paths.unshift(treeish)

      object_path = ['tree']
      paths.collect! do |path| 
        object_path << path
        "<a href=\"#{url(*object_path)}\">#{escape_html path}</a>"
      end

      paths.push(base) if base
      paths
    end
  end
end
