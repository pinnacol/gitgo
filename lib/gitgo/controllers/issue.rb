require 'gitgo/controller'
require 'gitgo/documents/issue'

module Gitgo
  module Controllers
    class Issue < Controller
      include Rest
      
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
        all = request['all']
        any = request['any']
        
        if tags = request['tags']
          tags = [tags] unless tags.kind_of?(Array)
          ((all ||= {})['tags'] ||= []).concat(tags)
        end
        
        issues = Issue.find(all, any)
        
        # sort results
        sort = request['sort'] || 'date'
        reverse = request['reverse'] == 'true'
        
        issues.sort! {|a, b| a[sort] <=> b[sort] }
        issues.reverse! if reverse
        
        erb :index, :locals => {
          :docs => issues,
          :any => any || {},
          :all => all || {},
          :sort => sort,
          :reverse => reverse, 
          :active_sha => session_head
        }
      end
      
      def tags
        repo.index.values('tags')
      end
      
      def model
        Issue
      end
      
      def attrs
        request['doc'] || {'tags' => ['open'], 'at' => session_head}
      end
    end
  end
end