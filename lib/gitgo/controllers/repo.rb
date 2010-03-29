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
      
      post('/repo/track')    { track }
      post('/repo/commit')   { commit }
      post('/repo/update')   { update }
      post('/repo/reindex')  { reset }
      post('/repo/reset')    { reset }
      post('/repo/prune')    { prune }
      post('/repo/gc')       { gc }
      post('/repo/setup')    { setup }
      
      #
      # actions
      #
      
      def index
        erb :index, :locals => {
          :path => git.path,
          :branch => git.branch,
          :commit => git.head.nil? ? nil : grit.commit(git.head),
          :upstream_branch => git.upstream_branch,
          :active_commit => head ? grit.commit(head) : nil
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
          :branch => git.branch,
          :head => head,
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
          Document.update_idx
          
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
        idx.clear
        
        if full = request['full']
          git.reset(full == 'true')
        end
        
        Document.update_idx
        redirect env['HTTP_REFERER'] || url('/repo')
      end
      
      def prune
        git.prune
        redirect url('/repo/maintenance')
      end
      
      def gc
        git.gc
        redirect url('/repo/maintenance')
      end
      
      def setup
        if branch = request['branch']
          git.checkout(branch)
        end
        
        if head = request['head']
          self.head = head.strip.empty? ? nil : head
        end
        
        redirect env['HTTP_REFERER'] || url('/repo')
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