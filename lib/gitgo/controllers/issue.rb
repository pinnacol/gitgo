require 'gitgo/controller'
require 'gitgo/documents/issue'

module Gitgo
  module Controllers
    class Issue < Controller
      set :views, File.expand_path("views/issue", ROOT)
      
      get('/issue')           { index }
      get('/issue/new')       { preview }
      get('/issue/:sha')      {|sha| show(sha) }
      get('/issue/:sha/edit') {|sha| edit(sha) }
      
      post('/issue')          { create }
      post('/issue/:sha')     {|sha|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(sha)
        when /\Adelete\z/i then destroy(sha)
        else create(sha)
        end
      }
      
      put('/issue/:sha')      {|sha| update(sha) }
      delete('/issue/:sha')   {|sha| destroy(sha) }
      
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
    
      def create(sha=nil)
        return(sha.nil? ? preview : show(sha)) if preview?
        
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
      
      def update(sha)
        return edit(sha) if preview?
        
        issue = Issue.update(sha, doc_attrs).commit!
        redirect_to_issue(issue)
      end
      
      def show(sha)
        unless issue = Issue.read(sha)
          raise "unknown issue: #{sha.inspect}"
        end
        
        current_tails = issue.graph_tails
        current_tags = []
        current_states = []
        current_tails.each do |tail|
          current_tags.concat tail.tags
          current_states << tail.state
        end
        current_tags.uniq!
        current_states.uniq!
        
        current_titles = issue.graph_heads.collect {|head| head.title }
        
        update = request['doc'] ? doc_attrs : {
          'tags' => current_tags, 
          'parents' => current_tails
        }
        
        erb :show, :locals => {
          :issue => issue,
          :update => update,
          :current_titles => current_titles,
          :current_tags => current_tags,
          :current_states => current_states
        }
      end
      
      def destroy(sha)
        issue = Issue.delete(sha).commit!
        redirect_to_issue(issue)
      end
      
      def doc_attrs
        attrs = request['doc'] || {}
        if tags = attrs['tags']
          if tags.kind_of?(String)
            attrs['tags'] = tags.split(',').collect {|tag| tag.strip }
          end
        end
        attrs
      end
      
      def redirect_to_issue(doc)
        sha = doc.graph_head? ? doc.graph.head : "#{doc.graph.head}##{doc.sha}"
        redirect "/issue/#{sha}"
      end
    end
  end
end