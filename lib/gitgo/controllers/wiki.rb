require 'gitgo/controller'

module Gitgo
  module Controllers
    class Wiki < Controller
      set :views, File.expand_path("views/wiki", ROOT)
      
      get("/wiki") { index }
      
      def index
        erb :index
      end
    end
  end
end