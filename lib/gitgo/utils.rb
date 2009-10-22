module Gitgo
  module Utils
    
    def grit
      repo.repo
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
    
    def latest(n=10, offest=0)
      latest = []
      
      years.reverse_each do |year|
        months(year).reverse_each do |month|
          days(year, month).reverse_each do |day|
            
            # y,m,d need to be iterated in reverse to correctly sort by
            # date; this is not the case with the unordered shas
            shas(year, month, day).each do |sha|
              if offest > 0
                offest -= 1
              else
                latest << sha
                return latest if n && latest.length > n
              end
            end
          end
        end
      end
      
      latest
    end

    def years
      return [] unless tree = repo["/"]
      tree.select {|dir| dir =~ /\A\d{4}\z/ }.sort
    end

    def months(year)
      repo["/%04d" % year.to_i].sort
    end

    def days(year, month)
      repo["/%04d/%02d" % [year.to_i, month.to_i]].sort
    end

    def shas(year, month, day)
      repo["/%04d/%02d/%02d" % [year.to_i, month.to_i, day.to_i]]
    end
    
    def render_comments(id)
      comments = repo.links(id) {|sha| repo.doc(sha) }
      if comments.empty?
        return erb(:_comment_form, :locals => {:id => id}, :layout => false)
      end
      
      @nesting_depth ||= 0
      @nesting_depth += 1
      result = erb :_comments, :locals => {
        :comments => comments, 
        :nesting_depth => @nesting_depth
      }, :layout => false
      @nesting_depth -= 1
    
      result
    end
    
    def commit(id)
      (id.length == 40 ? grit.commit(id) : nil) || commit_by_ref(id)
    end
    
    def commit_by_ref(name)
      ref = grit.refs.find {|ref| ref.name == name }
      ref ? ref.commit : nil
    end
  end
end
