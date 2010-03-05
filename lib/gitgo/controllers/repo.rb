require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :views, File.expand_path('views/repo', ROOT)
      
      get('/repo')           { index }
      get('/repo/idx')       { show_idx }
      get('/repo/idx/:key')  {|key| show_idx(key) }
      get('/repo/idx/:k/:v') {|key, value| show_idx(key, value) }
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
          :path => git.path,
          :branch => git.branch,
          :commit => git.head ? grit.commit(git.head) : nil,
          :remote => git.remote || Gitgo::Git::DEFAULT_REMOTE_BRANCH,
          :at => head
        }
      end
      
      def template(path)
        begin
          textile path.to_sym
        rescue(Errno::ENOENT)
          $!.message.include?(path) ? not_found : raise
        end
      end
      
      def show_idx(key=nil, value=nil)
        erb :idx, :locals => {
          :current_key => key,
          :index_keys => idx.keys.sort,
          :current_value => value,
          :index_values => key ? idx.values(key).sort : [],
          :shas => key && value ? idx.get(key, value).sort : []
        }
      end
      
      # (note status is taken as a method by Sinatra)
      def repo_status
        erb :status, :locals => {
          :branch => git.branch,
          :status => git.status(true)
        }
      end
      
      def maintenance
        erb :maintenance, :locals => {
          :keys => idx.keys,
          :issues => git.fsck.split("\n"),
          :stats => git.stats
        }
      end
      
      def setup
        raise "#{git.branch} branch already exists" if repo.head
        
        upstream_branch = request['track'].to_s
        if upstream_branch.empty?
          git['version'] = VERSION
          git.commit!('initial commit')
        else
          git.track(upstream_branch)
          git.merge
          Document.update_idx
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
        
        remote = request['remote'] || git.remote
        upstream_branch = request['upstream_branch'] || git.upstream_branch
        
        # Note that push and pull cannot be cleanly supported as separate
        # updates because pull can easily fail without a preceding pull. Since
        # there is no good way to detect that failure, see issue 7f7e85, the
        # next best option is to ensure a pull if doing a push.
        git.pull(remote, upstream_branch)
        git.push(remote) if request['sync'] == 'true'
        
        redirect url('/repo')
      end
      
      def reindex
        idx.clear
        Document.update_idx
        
        # allow redirection back to the specific key-value where the reindex occurred
        original_location = File.join('/repo/idx', request['key'].to_s, request['value'].to_s).chomp("/")
        redirect url(original_location)
      end
      
      def reset
        idx.clear
        git.reset(request['full'] == 'true')
        
        Document.update_idx
        redirect url('/repo')
      end
      
      def prune
        git.prune
        redirect url('/repo/maintenance')
      end
      
      def gc
        git.gc
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
      
      # Renders template as erb, then formats using RedCloth.
      def textile(template, options={}, locals={})
        require_warn('RedCloth') unless defined?(::RedCloth)

        # extract generic options
        layout = options.delete(:layout)
        layout = :layout if layout.nil? || layout == true
        views = options.delete(:views) || self.class.views || "./views"
        locals = options.delete(:locals) || locals || {}

        # render template
        data, options[:filename], options[:line] = lookup_template(:textile, template, views)
        output = format.textile render_erb(template, data, options, locals)
        
        # render layout
        if layout
          data, options[:filename], options[:line] = lookup_layout(:erb, layout, views)
          if data
            output = render_erb(layout, data, options, locals) { output }
          end
        end

        output
      end
    end
  end
end