require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :resource_name, "repo"
      set :views, "views/repo"
      
      get("/") do 
        erb :index, :locals => {
          :stats => repo.stats,
          :indexes => repo.list
        }
      end
      
      get("/status") do
        erb :status, :locals => {:status => repo.status}
      end
      
      get("/fsck") do
        erb :fsck, :locals => {:issues => repo.fsck}
      end
      
      post("/commit") do
        repo.commit request['message']
        redirect url("status")
      end
      
      post("/reindex") do
        repo.reindex!
        redirect url
      end
      
      post("/reset") do
        repo.reset
        redirect url("status")
      end
    end
  end
end