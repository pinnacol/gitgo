require 'gitgo/repo'
require 'gitgo/comments'

module Gitgo
  class Server < Controller
        
    # Page routing (public, then views/*.textile)
    set :static, true
    set :views, "views/server"
    
    get("/")  { erb :index }
    get('/commit')      { show_commit('master') }
    get('/commit/:id')  {|id| show_commit(id) }
    get('/tree')        { show_tree("master") }
    get('/tree/:id')    {|id| show_tree(id) }
    get('/tree/:id/*')  {|id, path| show_tree(id, path) }
    get('/blob/:id/*')  {|id, path| show_blob(id, path) }
    get('/show/:sha')   {|sha| show_sha(sha) }
    get("/:id/commits") {|id| show_history(id) }
    
    use Comments
    
    def grit
      repo.repo
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
    
    def show_sha(sha)
      case repo.type(sha)
      when "blob"
        erb :sha_blob, :locals => {:blob => grit.blob(sha)}
      when "tree"
        erb :sha_tree, :locals => {:tree => grit.tree(sha)}
      when "commit", "tag"
        erb :diff, :locals => {:commit => grit.commit(sha)}
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
    
    def commit(id)
      (id.length == 40 ? grit.commit(id) : nil) || commit_by_ref(id)
    end
    
    def commit_by_ref(name)
      ref = grit.refs.find {|ref| ref.name == name }
      ref ? ref.commit : nil
    end
  end
end