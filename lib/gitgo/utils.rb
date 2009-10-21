module Gitgo
  module Utils
    def commit_link(id)
      %Q{<a href="/commit/#{id}">#{id}</a>}
    end

    def tree_link(id, *paths)
      path = paths.empty? ? id : File.join(id, *paths)
      %Q{<a href="/tree/#{path}">#{File.basename(path)}</a>}
    end

    def blob_link(id, *paths)
      path = File.join(id, *paths)
      %Q{<a href="/blob/#{path}">#{File.basename(path)}</a>}
    end

    def show_link(obj)
      %Q{<a href="/show/#{obj.id}">#{obj.name}</a>}
    end
    
    def sha_link(sha)
      %Q{<a href="/show/#{sha}">#{sha}</a>}
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
  end
end
