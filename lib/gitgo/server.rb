require 'gitgo/repo'
require 'gitgo/controller'

module Gitgo
  class Server < Controller
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
    
    include Utils
    
    # Page routing (public, then views/*.textile)
    set :static, true
    set :views, "views/server"
    
    get("/")  { erb :index }
    get('/commit')     { show_commit('master') }
    get('/commit/:id') {|id| show_commit(id) }
    get('/tree')       { show_tree("master") }
    get('/tree/:id')   {|id| show_tree(id) }
    get('/tree/:id/*') {|id, path| show_tree(id, path) }
    get('/blob/:id/*') {|id, path| show_blob(id, path) }
    get("/:id/commits") do |id|
      commit = self.commit(id)
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 10).to_i
      
      erb :commits, :locals => {
        :id => id,
        :page => page,
        :per_page => per_page,
        :commits => grit.commits(commit.sha, per_page, page * per_page)
      }
    end
    
    def grit
      repo.repo
    end
    
    def show_commit(id)
      commit = self.commit(id) || not_found
      erb :diff, :locals => {:commit => commit, :id => id }
    end
    
    def show_tree(id, path="")
      commit = self.commit(id) || not_found
      tree = path.split("/").inject(commit.tree) do |obj, name|
        not_found if obj.nil?
        obj.trees.find {|obj| obj.name == name }
      end
      
      erb :tree, :locals => {:commit => commit, :tree => tree, :id => id, :path => path}
    end
    
    def show_blob(id, path)
      commit = self.commit(id)  || not_found
      blob = commit.tree / path || not_found
      
      erb :blob, :locals => {:commit => commit, :blob => blob, :id => id, :path => path }
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