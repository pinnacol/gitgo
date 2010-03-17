require 'gitgo/controller'
require 'gitgo/documents/issue'

module Gitgo
  module Controllers
    class Issue < Controller
      set :views, File.expand_path("views/issue", ROOT)
      
      get('/issue')        { index }
      get('/issue/new')    { preview }
      get('/issue/:id')    {|id| show(id) }
      
      post('/issue')       { create }
      post('/issue/:id') do |id|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(id)
        when /\Adelete\z/i then destroy(id)
        else raise("unknown post method: #{_method}")
        end
      end
      
      put('/issue/:id')    {|id| update(id) }
      delete('/issue/:id') {|id| destroy(id) }
      
      #
      # actions
      #
      
      Issue = Documents::Issue
      
      # Processes requests like: /index?key=value
      #
      # Where the key-value pairs are filter criteria.  Multiple criteria can
      # be specified per-request (ex a[]=one&a[]=two&b=three).  Any of the
      # Issue::ATTRIBUTES can be used to filter.
      #
      # Sort on a specific key using sort=key (date is the default).  Reverse
      # the sort with reverse=true. Multiple sort criteria are currently not
      # supported.
      def index
        criteria = {
          'state' => request['state'] || [],
          'tags'  => request['tags'] || []
        }.delete_if {|key, value| value.empty? }
        
        issues = Issue.find(criteria)
        
        # sort results
        sort = request['sort'] || 'date'
        reverse = request['reverse'] == 'true'
        
        issues.sort! {|a, b| a[sort] <=> b[sort] }
        issues.reverse! if reverse
        
        erb :index, :locals => {
          :issues => issues,
          :tags => criteria['tags'],
          :state => criteria['state'],
          :sort => sort,
          :reverse => reverse
        }
      end
    
      def preview
        erb :new, :locals => {
          :doc => request['doc'] || {}
        }
      end
    
      def create
        return preview if request['preview'] == 'true'
        
        issue = Issue.create(request['doc'])
        repo.commit! if request['commit']
        redirect_to_origin(issue)
      end
      
      def show(issue)
        unless issue = Issue.read(issue)
          raise "unknown issue: #{issue.inspect}"
        end
        
        erb :show, :locals => {:issue => issue}
      end
      
      def update(sha)
        issue = Issue.update(sha, request['doc'])
        repo.commit! if request['commit']
        redirect_to_origin(issue)
      end

      def destroy(sha)
        issue = Issue.delete(sha)
        repo.commit! if request['commit']
        redirect_to_origin(issue)
      end
    end
  end
end