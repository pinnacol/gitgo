require 'gitgo/repo'
require 'gitgo/documents'

module Gitgo
  class Server < Controller
        
    # Page routing (public, then views/*.textile)
    set :static, true
    set :views, "views/server"
    
    get("/")            { index }
    get('/commit')      { show_commit('master') }
    get('/commit/:id')  {|id| show_commit(id) }
    get('/tree')        { show_tree("master") }
    get('/tree/:id')    {|id| show_tree(id) }
    get('/tree/:id/*')  {|id, path| show_tree(id, path) }
    get('/blob/:id/*')  {|id, path| show_blob(id, path) }
    get('/show/:sha')   {|sha| show_sha(sha) }
    get("/:id/commits") {|id| show_history(id) }
    
    use Documents

    def index
      erb :index, :locals => {
        :branches => grit.branches,
        :tags => grit.tags,
        :timeline => latest
      } 
    end
    
    def show_commit(id)
      commit = self.commit(id) || not_found
      erb :diff, :locals => {:commit => commit}
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
    
    def show_sha(id)
      case repo.type(id)
      when "blob"
        erb :sha_blob, :locals => {:id => id, :blob => grit.blob(id)}
      when "tree"
        erb :sha_tree, :locals => {:id => id, :tree => grit.tree(id)}
      when "commit", "tag"
        erb :diff, :locals => {:id => id, :commit => grit.commit(id)}
      else not_found
      end
    end
    
    def show_history(id)
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
  end
end