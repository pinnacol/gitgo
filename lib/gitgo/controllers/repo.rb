require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :views, File.expand_path('views/repo', ROOT)
      
      get('/repo')           { index }
      get('/repo/idx')       { idx }
      get('/repo/idx/:key')  {|key| idx(key) }
      get('/repo/idx/:k/:v') {|key, value| idx(key, value) }
      get('/repo/status')    { repo_status }
      get('/repo/maintenance') { maintenance }
      get('/repo/*')         {|path| template(path) }
      
      post('/repo/setup')    { setup }
      post('/repo/commit')   { commit }
      post('/repo/update')   { update }
      post('/repo/reindex')  { reindex }
      post('/repo/reset')    { reset }
      post('/repo/prune')    { prune }
      post('/repo/gc')       { gc }
      post('/repo/session')  { update_session }
      
      #
      # actions
      #
      
      def index
        erb :index, :locals => {
          :track => repo.track || Gitgo::Repo::DEFAULT_TRACK_BRANCH,
          :commit => grit.commit(repo.head),
          :path => repo.path,
          :branch => repo.branch
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
          :index_keys => repo.index.keys.sort,
          :current_value => value,
          :index_values => key ? repo.index.values(key).sort : [],
          :shas => key && value ? repo.index.read(key, value).sort : []
        }
      end
      
      # (note status is taken as a method by Sinatra)
      def repo_status
        erb :status, :locals => {:status => repo.status(true)}
      end
      
      def maintenance
        erb :maintenance, :locals => {
          :keys => repo.index.keys,
          :issues => repo.fsck.split("\n"),
          :stats => repo.stats
        }
      end
      
      def setup
        raise "#{repo.branch} already exists" if repo.head
        
        remote = request['remote']
        if remote.to_s.empty?
          repo.create('initialized gitgo')
          repo.commit!('initial commit')
        else
          repo.sandbox do |git, w, i|
            git.branch({:track => true}, repo.branch, remote)
          end
          repo.reset
        end
        
        redirect url('/repo')
      end
      
      def commit
        repo.commit request['message']
        redirect url('/repo/status')
      end
      
      def update
        unless repo.status.empty?
          raise 'local changes; cannot update'
        end
        
        ref = request['remote'] || repo.track
        remote, remote_branch = ref.split("/", 2)
        
        # Note that push and pull cannot be cleanly supported as separate
        # updates because pull can easily fail without a preceding pull. Since
        # there is no good way to detect that failure, see issue 7f7e85, the
        # next best option is to ensure a pull if doing a push.
        repo.pull(remote, ref)
        repo.push(remote) if request['sync'] == 'true'
        
        redirect url('/repo')
      end
      
      def reindex
        repo.index.clear
        repo.reindex
        
        # allow redirection back to the specific key-value where the reindex occurred
        original_location = File.join('/repo/idx', request['key'].to_s, request['value'].to_s).chomp("/")
        redirect url(original_location)
      end
      
      def reset
        repo.index.clear
        repo.reset(:full => request['full'] == 'true')
        redirect url('/repo')
      end
      
      def prune
        repo.prune
        redirect url('/repo/maintenance')
      end
      
      def gc
        repo.gc
        redirect url('/repo/maintenance')
      end
      
      def update_session
        if ref = request['ref']
          session['at'] = ref
        else
          session.delete('at')
        end
        
        redirect url('/repo')
      end
    end
  end
end