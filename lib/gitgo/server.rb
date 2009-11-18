require 'gitgo/controller'
require 'gitgo/controllers/code'
require 'gitgo/controllers/issue'
require 'gitgo/controllers/repo'
require 'gitgo/controllers/wiki'

module Gitgo
  class Server < Controller
    set :views, "views/server"
    
    set :static, true
    get("/")            { index }
    
    use Controllers::Code
    use Controllers::Issue
    use Controllers::Wiki
    use Controllers::Repo
    
    def index
      erb :index
    end
  end
end