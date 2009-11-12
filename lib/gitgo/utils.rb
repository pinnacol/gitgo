module Gitgo
  module Utils
    
    def grit
      repo.grit
    end
    
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
    
    def render_comments(id)
      comments = repo.children(id).collect! {|sha| repo.read(sha) }
      
      if comments.empty?
        erb :_comment_form, :locals => {
          :id => id
        }, :views => "views/comments", :layout => false
        
      else
        @nesting_depth ||= 0
        @nesting_depth += 1
        result = erb :_comments, :locals => {
          :comments => comments, 
          :nesting_depth => @nesting_depth
        }, :views => "views/comments", :layout => false
        @nesting_depth -= 1
    
        result
      end
    end
    
    def commit(id)
      (id.length == 40 ? grit.commit(id) : nil) || commit_by_ref(id)
    end
    
    def commit_by_ref(name)
      ref = grit.refs.find {|ref| ref.name == name }
      ref ? ref.commit : nil
    end
    
    def flatten(ancestry)
      ancestry.each_pair do |parent, children|
        children.collect! {|child| ancestry[child] }
        children.unshift(parent)
      end
      ancestry
    end
    
    def collapse(array, result=[])
      result << array.shift
      
      if array.length == 1
        collapse(array.shift, result)
      else
        array.each do |sub|
          result << collapse(sub)
        end
      end
      
      result
    end
  end
end
