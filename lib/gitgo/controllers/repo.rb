require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :views, File.expand_path("views/repo", ROOT)
      
      get("/repo")           { index }
      get("/repo/idx")       { idx }
      get("/repo/idx/:key")  {|key| idx(key) }
      get("/repo/idx/:k/:v") {|key, value| idx(key, value) }
      get("/repo/status")    { repo_status }
      get("/repo/maintenance") { maintenance }
      get("/repo/*")         {|path| template(path) }
      
      post("/repo/setup")    { setup }
      post("/repo/commit")   { commit }
      post("/repo/update")   { update }
      post("/repo/reindex")  { reindex }
      post("/repo/reset")    { reset }
      post("/repo/prune")    { prune }
      post("/repo/gc")       { gc }
      
      #
      # actions
      #
      
      def index
        erb :index, :locals => {
          :keys => repo.list, 
          :remotes => repo.grit.remotes.collect {|remote| remote.name }.sort,
          :track => repo.track,
          :current => repo.current
        }
      end
      
      def template(path)
        begin
          textile path.to_sym
        rescue(Errno::ENOENT)
          $!.message.include?(path) ? not_found : raise
        end
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
      
      # (note status is taken as a method by Sinatra)
      def repo_status
        erb :status, :locals => {:status => repo.status(true)}
      end
      
      def maintenance
        erb :maintenance, :locals => {
          :keys => repo.list,
          :issues => repo.fsck,
          :stats => repo.stats
        }
      end
      
      def setup
        raise "#{repo.branch} already exists" if repo.current
        
        remote = request['remote']
        if remote.empty?
          repo.create("initialized gitgo")
          repo.commit!("initial commit")
        else
          repo.sandbox do |git, w, i|
            git.branch({:track => true}, repo.branch, remote)
          end
          repo.reindex!(true)
        end
        
        redirect url("/repo")
      end
      
      def commit
        repo.commit request['message']
        redirect url("/repo/status")
      end
      
      def update
        if set?("reset")
          repo.reset
          repo.reindex!(true)
        end
        
        unless repo.status.empty?
          raise "local changes; cannot update"
        end
        
        ref = request['remote'] || repo.track
        remote, remote_branch = ref.split("/", 2)
        
        repo.pull(remote, ref) if set?("pull")
        repo.push(remote) if set?("push")
        
        redirect url("/repo")
      end
      
      def reindex
        repo.reindex! set?('full')
        redirect url("/repo")
      end
      
      def reset
        repo.reset
        redirect url("/repo/status")
      end
      
      def prune
        repo.prune
        redirect url("/repo/maintenance")
      end
      
      def gc
        repo.gc
        redirect url("/repo/maintenance")
      end
    end
  end
end