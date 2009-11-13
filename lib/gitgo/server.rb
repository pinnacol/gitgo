require 'gitgo/controller'
require 'gitgo/controllers/comment'
require 'gitgo/controllers/issue'

module Gitgo
  class Server < Controller
    include Controllers
    
    # Page routing (public, then views/*.textile)
    set :static, true
    set :views, "views/server"
    
    get("/")            { index }
    get("/code")        { code_index }
    get('/commit')      { show_commit('master') }
    get('/commit/:id')  {|id| show_commit(id) }
    get('/tree')        { show_tree("master") }
    get('/tree/:id')    {|id| show_tree(id) }
    get('/tree/:id/*')  {|id, path| show_tree(id, path) }
    get('/blob/:id/*')  {|id, path| show_blob(id, path) }
    get('/show/:id')    {|id| show_sha(id) }
    get('/doc/:id')     {|id| show_doc(id) }
    get("/:id/commits") {|id| show_history(id) }
    
    use Comment
    use Issue
    
    def index
      erb :index
    end
    
    def code_index
      erb :code, :locals => {
        :branches => grit.branches,
        :tags => grit.tags
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
    
    def show_doc(id)
      if document = repo.read(id)
        erb :document, :locals => {:document => document}
      else
        not_found
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