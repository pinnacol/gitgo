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
    # get('/commit')      { show_commit('master') }
    get('/commit/:commit')  {|commit| show_commit(commit) }
    # get('/tree')        { show_tree("master") }
    get('/tree/:commit')    {|commit| show_tree(commit) }
    get('/tree/:commit/*')  {|commit, path| show_tree(commit, path) }
    get('/blob/:commit/*')  {|commit, path| show_blob(commit, path) }
    get('/obj/:sha')        {|sha| show_object(sha) }
    
    # get("/:id/commits") {|id| show_history(id) }
    
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
    
    def show_object(id)
      case
      when set?('content')
        response['Content-Type'] = "text/plain"
        grit.git.cat_file({:p => true}, id)
        
      when set?('download')
        response['Content-Type'] = "text/plain"
        response['Content-Disposition'] = "attachment; filename=#{id};"
        raw_object = grit.git.ruby_git.get_raw_object_by_sha1(id)
        "%s %d\0" % [raw_object.type, raw_object.content.length] + raw_object.content
        
      else
        case repo.type(id)
        when "blob"
          erb :blob, :locals => {:id => id, :blob => grit.blob(id)}, :views => "views/obj"
        when "tree"
          erb :tree, :locals => {:id => id, :tree => grit.tree(id)}, :views => "views/obj"
        when "commit"
          erb :commit, :locals => {:id => id, :commit => grit.commit(id)}, :views => "views/obj"
        # when "tag"
        #   erb :tag, :locals => {:id => id, :tag => }, :views => "views/obj"
        else not_found
        end
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