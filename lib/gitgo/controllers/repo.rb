require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :views, File.expand_path('views/repo', ROOT)
      
      get('/repo')           { index }
      get('/repo/index')       { show_idx }
      get('/repo/index/:key')  {|key| show_idx(key) }
      get('/repo/index/:k/:v') {|key, value| show_idx(key, value) }
      get('/repo/status')    { repo_status }
      get('/repo/fsck') { fsck }
      get('/repo/*')         {|path| template(path) }
      
      post('/repo/track')    { track }
      post('/repo/commit')   { commit }
      post('/repo/update')   { update }
      post('/repo/reindex')  { reset }
      post('/repo/reset')    { reset }
      post('/repo/prune')    { prune }
      post('/repo/gc')       { gc }
      post('/repo/setup')    { setup }
      
      def git
        @git ||= repo.git
      end
      
      def grit
        @grit ||= git.grit
      end
      
      #
      # actions
      #
      
      def index
        erb :index, :locals => {
          :path => repo.path,
          :branch => repo.branch,
          :commit => repo.head.nil? ? nil : grit.commit(repo.head),
          :upstream_branch => repo.upstream_branch,
          :refs => repo.refs,
          :active_sha => session_head,
          :active_commit => session_head ? grit.commit(session_head) : nil,
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
        index = repo.index
        
        erb :idx, :locals => {
          :current_key => key,
          :index_keys => index.keys.sort,
          :current_value => value,
          :index_values => key ? index.values(key).sort : [],
          :shas => key && value ? index[key][value].collect {|idx| index.list[idx] } : index.list
        }
      end
      
      # (note status is taken as a method by Sinatra)
      def repo_status
        erb :status, :locals => {
          :branch => git.branch,
          :status => git.status(true)
        }
      end
      
      def fsck
        erb :fsck, :locals => {
          :branch => git.branch,
          :head => session_head,
          :issues => git.fsck.split("\n"),
          :stats => git.stats
        }
      end
      
      def commit
        repo.commit request['message']
        redirect url('/repo/status')
      end
      
      def update
        unless repo.status.empty?
          raise 'local changes; cannot update'
        end
        
        upstream_branch = request['upstream_branch'] || git.upstream_branch
        unless upstream_branch.nil? || upstream_branch.empty?
          
          # Note that push and pull cannot be cleanly supported as separate
          # updates because pull can easily fail without a preceding pull. Since
          # there is no good way to detect that failure, see issue 7f7e85, the
          # next best option is to ensure a pull if doing a push.
          git.pull(upstream_branch)
          Document.update_index
          
          if request['sync'] == 'true'
            git.push(upstream_branch)
          end
        end
        
        redirect url('/repo')
      end
      
      def track
        tracking_branch = request['tracking_branch']
        git.track(tracking_branch.empty? ? nil : tracking_branch)
        
        redirect url('/repo')
      end
      
      def reset
        repo.index.clear
        
        if full = request['full']
          git.reset(full == 'true')
        end
        
        Document.update_index
        redirect env['HTTP_REFERER'] || url('/repo')
      end
      
      def prune
        git.prune
        redirect url('/repo/fsck')
      end
      
      def gc
        git.gc
        redirect url('/repo/fsck')
      end
      
      def setup
        gitgo = request['gitgo'] || {}
        if branch = gitgo['branch']
          repo.checkout(branch)
        end
        
        if upstream_branch = request['upstream_branch']
          repo.setup(upstream_branch)
        end
        
        session = request['session'] || {}
        if head = session['head']
          self.session_head = head.strip.empty? ? nil : head
        end
        
        redirect request['redirect'] || env['HTTP_REFERER'] || url('/repo')
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