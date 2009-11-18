require 'gitgo/controller'

module Gitgo
  module Controllers
    class Wiki < Controller
      set :resource_name, "wiki"
      set :views, "views/wiki"
      
      get("/") { index }
      
      def index
        erb :index
      end
    end
  end
end