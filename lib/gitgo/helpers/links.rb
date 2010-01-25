module Gitgo
  module Helpers
    module Links
      # Currently returns the path directly.  Provided as a hook for future use.
      def url(path="/")
        path
      end
      
      def commit_link(sha)
        %Q{<a href="/commit/#{sha}">#{sha}</a>}
      end

      def tree_link(treeish, *paths)
        path = paths.empty? ? treeish : File.join(treeish, *paths)
        %Q{<a href="/tree/#{path}">#{File.basename(path)}</a>}
      end

      def blob_link(treeish, *paths)
        path = File.join(treeish, *paths)
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

      def path_links(treeish, path)
        paths = path.split("/")
        base = paths.pop
        paths.unshift(treeish)

        object_path = ""
        paths.collect! do |path| 
          object_path = File.join(object_path, path)
          %Q{<a href="/tree#{object_path}">#{path}</a>}
        end

        paths.push(base) if base
        paths
      end
    end
  end
end