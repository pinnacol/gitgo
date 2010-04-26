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
      
      def preview?
        request['preview'] == 'true'
      end
      
      def preview
        doc = Issue.new(attrs)
        # doc.normalize!
        erb :new, :locals => {:doc => doc}
      end
    
      def create(sha=nil)
        return(sha.nil? ? preview : show(sha)) if preview?
        
        doc = Issue.save(attrs)
        
        parents = request['parents']
        if parents.nil? || parents.empty?
          doc.create
        else
          parents = [parents] unless parents.kind_of?(Array)
          parents.collect! do |parent|
            Issue[parent] or raise "invalid parent: #{parent.inspect}"
          end
          doc.link_to(*parents)
        end
        
        doc.commit!
        redirect_to_doc(doc)
      end
      
      def edit(sha)
        unless doc = Issue.read(sha)
          raise "unknown issue: #{sha.inspect}"
        end
        
        doc.merge!(attrs)
        erb :edit, :locals => {:doc => doc}
      end
      
      def update(sha)
        return edit(sha) if preview?
        
        doc = Issue.update(sha, attrs).commit!
        redirect_to_doc(doc)
      end
      
      def show(sha)
        unless doc = Issue.read(sha)
          raise "unknown issue: #{sha.inspect}"
        end
        
        new_doc = doc.inherit(attrs)
        # new_doc.normalize!
        
        erb :show, :locals => {
          :doc => doc,
          :new_doc => new_doc,
          :active_sha => session_head
        }
      end
      
      def destroy(sha)
        doc = Issue.delete(sha).commit!
        
        if doc.graph_head?
          redirect "/issue"
        else
          redirect_to_doc(doc)
        end
      end
      
      def attrs
        request['doc'] || {'tags' => ['open'], 'at' => session_head}
      end
      
      def redirect_to_doc(doc)
        sha = doc.graph_head? ? doc.graph.head : "#{doc.graph.head}##{doc.sha}"
        redirect "/issue/#{sha}"
      end
    end
  end
end