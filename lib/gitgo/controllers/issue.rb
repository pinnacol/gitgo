require 'gitgo/controller'
require 'gitgo/documents/issue'

module Gitgo
  module Controllers
    class Issue < Controller
      set :views, File.expand_path("views/issue", ROOT)
      
      get('/issue')        { index }
      get('/issue/new')    { preview }
      get('/issue/:id')      {|id| show(id) }
      get('/issue/:id/edit') {|id| edit(id) }
      
      post('/issue')         { create }
      post('/issue/:id') do |id|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(id)
        when /\Arevise\z/i then revise(id)
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
        states = request['state'] || []
        tags = request['tags'] || []
        
        issues = Issue.find('state' => states, 'tags' => tags)
        
        # sort results
        sort = request['sort'] || 'date'
        reverse = request['reverse'] == 'true'
        
        issues.sort! {|a, b| a[sort] <=> b[sort] }
        issues.reverse! if reverse
        
        erb :index, :locals => {
          :issues => issues,
          :states => states,
          :tags => tags,
          :sort => sort,
          :reverse => reverse, 
          :active_sha => head
        }
      end
      
      def preview?
        request['preview'] == 'true'
      end
      
      def preview
        erb :new, :locals => {:doc => doc_attrs}
      end
    
      def create
        return preview if preview?
        
        issue = Issue.create(doc_attrs).commit!
        redirect_to_issue(issue)
      end
      
      def edit(sha)
        unless issue = Issue.read(sha)
          raise "unknown issue: #{sha.inspect}"
        end
        
        issue.merge!(doc_attrs)
        erb :edit, :locals => {:issue => issue}
      end
      
      def revise(sha)
        return edit(sha) if preview?
        
        issue = Issue.update(sha, doc_attrs).commit!
        redirect_to_issue(issue)
      end
      
      def show(sha)
        unless issue = Issue.read(sha)
          raise "unknown issue: #{sha.inspect}"
        end
        
        update = request['doc'] ? doc_attrs : {
          'tags' => issue.current_tags, 
          'parents' => issue.graph.tails.dup
        }
        
        erb :show, :locals => {
          :issue => issue,
          :update => update,
          :current_titles => issue.titles,
          :current_tags => issue.current_tags,
          :current_states => issue.current_states
        }
      end
      
      def update(sha)
        return show(sha) if preview?
        
        issue = Issue.create(doc_attrs).commit!
        redirect_to_issue(issue)
      end

      def destroy(sha)
        issue = Issue.delete(sha).commit!
        redirect_to_issue(issue)
      end
      
      def doc_attrs
        attrs = request['doc'] || {}
        if tags = attrs['tags']
          attrs['tags'] = tags.split(',').collect {|tag| tag.strip }
        end
        attrs
      end
      
      def redirect_to_issue(doc)
        sha = doc.origin? ? "#{doc.origin}##{doc.sha}" : doc.origin
        redirect "/issue/#{sha}"
      end
    end
  end
end