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
      
      def index
        any = request['any']
        all = request['all']
        issues = Issue.find(all, any)
        
        # sort results
        sort = request['sort'] || 'date'
        reverse = request['reverse'] == 'true'
        
        issues.sort! {|a, b| a[sort] <=> b[sort] }
        issues.reverse! if reverse
        
        erb :index, :locals => {
          :issues => issues,
          :any => any || {},
          :all => all || {},
          :tags => repo.index.values('tags'),
          :sort => sort,
          :reverse => reverse, 
          :active_sha => session_head
        }
      end
      
      def preview?
        request['preview'] == 'true'
      end
      
      def preview
        erb :new, :locals => {:doc => Issue.new(doc_attrs)}
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
        
        erb :show, :locals => {
          :issue => issue,
          :doc => issue.inherit(doc_attrs),
          :active_sha => session_head
        }
      end
      
      def destroy(sha)
        issue = Issue.delete(sha).commit!
        redirect_to_issue(issue)
      end
      
      def doc_attrs
        attrs = request['doc'] || {'at' => session_head}
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