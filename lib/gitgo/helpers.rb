require 'redcloth'
require 'rack/utils'

module Gitgo
  module Helpers
    include Rack::Utils
    
    def grit
      repo.grit
    end
    
    def gformat(str)
      str = escape_html(str)
      str.gsub!(/[a-f0-9]{40}/) {|sha| sha_link(sha) }
      str
    end
    
    def tformat(str)
      ::RedCloth.new(gformat(str)).to_html
    end
    
    def commit_link(commit)
      %Q{<a href="/commit/#{commit}">#{commit}</a>}
    end

    def tree_link(commit, *paths)
      path = paths.empty? ? commit : File.join(commit, *paths)
      %Q{<a href="/tree/#{path}">#{File.basename(path)}</a>}
    end

    def blob_link(commit, *paths)
      path = File.join(commit, *paths)
      %Q{<a href="/blob/#{path}">#{File.basename(path)}</a>}
    end

    def obj_link(sha)
      "#{sha_link(sha)} (#{repo.type(sha)})"
    end
    
    def show_link(obj)
      %Q{<a href="/obj/#{obj.id}">#{obj.name}</a>}
    end
    
    def sha_link(sha)
      %Q{<a href="/obj/#{sha}">#{sha}</a>}
    end
    
    def activity_link(author)
      %Q{#{author.name} (<a href="/timeline?author=#{author.email}">#{author.email}</a>)}
    end
    
    def commits_link(ref)
      %Q{<a href="/commits/#{ref}">history</a>}
    end
    
    def issue_link(doc)
      title = doc['title']
      title = "(nameless issue)" if title.to_s.empty?
      %Q{<a class="#{doc['state']}" href="/issue/#{doc.sha}">#{title}</a>}
    end
    
    def path_links(id, path)
      paths = path.split("/")
      base = paths.pop
      paths.unshift(id)

      current = ""
      paths.collect! do |path| 
        current = File.join(current, path)
        %Q{<a href="/tree#{current}">#{path}</a>}
      end

      paths.push(base) if base
      paths
    end
    
    def head
      grit.head
    end
    
    def refs(remotes=false)
      refs = grit.refs
      unless remotes
        refs.delete_if {|ref| ref.kind_of?(Grit::Remote) }
      end
      refs
    end
    
    def commit(id)
      (id.length == 40 ? grit.commit(id) : nil) || commit_by_ref(id)
    end
    
    def commit_by_ref(name)
      ref = grit.refs.find {|ref| ref.name == name }
      ref ? ref.commit : nil
    end
    
    # Returns a title for pages served from this controller; either the
    # capitalized resource name or the class basename.
    def title
      self.class.to_s.split("::").last.capitalize
    end
    
    # Renders template as erb, then formats using RedCloth.
    def textile(template, options={}, locals={})
      require_warn('RedCloth') unless defined?(::RedCloth)
      
      # extract generic options
      layout = options.delete(:layout)
      layout = :layout if layout.nil? || layout == true
      views = options.delete(:views) || self.class.views || "./views"
      locals = options.delete(:locals) || locals || {}

      # render template
      data, options[:filename], options[:line] = lookup_template(:textile, template, views)
      output = render_erb(template, data, options, locals)
      output = ::RedCloth.new(output).to_html
      
      # render layout
      if layout
        data, options[:filename], options[:line] = lookup_layout(:erb, layout, views)
        if data
          output = render_erb(layout, data, options, locals) { output }
        end
      end

      output
    end
  end
end
