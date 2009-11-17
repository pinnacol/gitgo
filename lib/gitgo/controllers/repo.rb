require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :resource_name, "repo"
      set :views, "views/repo"
      
      get("/")          { index }
      get("/idx")       { idx }
      get("/idx/:key")  {|key| idx(key) }
      get("/idx/:k/:v") {|key, value| idx(key, value) }
      get("/status")    { status }
      get("/fsck")      { fsck }
      post("/commit")   { commit }
      post("/reindex")  { reindex }
      post("/reset")    { reset }
      
      def index
        erb :index, :locals => {
          :stats => repo.stats,
          :keys => repo.list
        }
      end
      
      def idx(key=nil, value=nil)
        erb :idx, :locals => {
          :current_key => key,
          :keys => repo.list,
          :current_value => value,
          :values => key ? repo.list(key) : [],
          :shas => key && value ? repo.index(key, value) : []
        }
      end
      
      def status
        erb :status, :locals => {:status => repo.status}
      end
      
      def fsck
        erb :fsck, :locals => {:issues => repo.fsck}
      end
      
      def commit
        repo.commit request['message']
        redirect url("status")
      end
      
      def reindex
        repo.reindex! set?('full')
        redirect url
      end
      
      def reset
        repo.reset
        redirect url("status")
      end
    end
  end
end