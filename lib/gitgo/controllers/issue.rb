require 'gitgo/controller'

module Gitgo
  module Controllers
    class Issue < Controller
      set :views, File.expand_path("views/issue", ROOT)

      get('/issue')        { index }
      get('/issue/new')    { preview }
      get('/issue/:id')    {|id| show(id) }
      get('/issue/:id/:update') {|id, update| show(id, update) }
      
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
      
      INHERIT = %w{state tags}
      ATTRIBUTES = %w{author date state tags}
      
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
        # filter issues
        criteria = {}
        ATTRIBUTES.each do |key|
          next unless values = params[key]
          criteria[key] = values.kind_of?(Array) ? values : [values]
        end
      
        filters = []
        criteria.each_pair do |key, values|
          filter = values.collect do |value|
            repo.index.read(key, value)
          end.flatten
        
          filters << filter
        end
        
        issues = []
        repo.index.read("type", "issue").each do |sha|
          tails = repo.tails(sha)
          filters.each do |filter|
            tails = tails & filter
          end
          
          unless tails.empty?
            # note this lookup is deadly slow.
            doc = cache[sha]
            doc[:active] = tails.any? {|tail| active?(cache[tail]['at']) } ? true : active?(doc['at'])
            
            issues << doc
          end
        end
        
        # sort results
        sort_attr = request['sort'] || 'date'
        reverse = request['reverse'] == 'true'
        
        issues.sort! {|a, b| a[sort_attr] <=> b[sort_attr] }
        issues.reverse! if reverse
        
        erb :index, :locals => {
          :issues => issues,
          :current_states => criteria['state'] || [],
          :current_tags => criteria['tags'] || [],
          :sort_attr => sort_attr,
          :reverse => reverse
        }
      end
    
      def preview
        erb :new, :locals => {
          :doc => request['doc'] || {}, 
          :content => request['content']
        }
      end
    
      def create
        return preview if request['preview'] == 'true'
      
        doc = document('type' => 'issue', 'state' => 'open')
        if doc['title'].to_s.strip.empty? && doc.empty?
          raise "no title or content specified"
        end
        issue = repo.store(doc, :rev_parse => ['at'])
      
        # if specified, link the issue to a commit
        if commit = doc['at']
          repo.link(commit, issue, :ref => issue)
        end
      
        repo.commit!("issue #{issue}") if request['commit'] == 'true'
        redirect url("/issue/#{issue}")
      end
    
      def show(issue, update=nil)
        unless doc = cache[issue]
          raise "unknown issue: #{issue.inspect}"
        end
        issue = doc.sha
        
        # get updates
        updates = repo.comments(issue, cache)
        
        # resolve tails
        tails = cache.keys.collect {|sha| cache[sha] }.select {|document| document && document[:tail] }
        tails << doc if tails.empty?
        
        tail_states = []
        tail_tags = []
        tails.each do |document|
          tail_states << document['state']
          tail_tags.concat(document.tags)
        end
        tail_states.uniq!
        tail_tags.uniq!
      
        erb :show, :locals => {
          :doc => doc,
          :updates => updates,
          :tails => tails,
          :tail_states => tail_states,
          :tail_tags => tail_tags
        }
      end
    
      # Update adds a comment to the specified issue.
      def update(issue)
        unless doc = cache[issue]
          raise "unknown issue: #{issue.inspect}"
        end
        issue = doc.sha
        
        # the comment is always in regards to the issue internally (ie re => issue)
        doc = inherit(doc, 'type' => 'update', 're' => issue)
        update = repo.store(doc, :rev_parse => ['at', 're'])

        # link the comment to each parent and update the index
        parents = request['re'] || [issue]
        parents = [parents] unless parents.kind_of?(Array)
        parents.each do |parent|
          unless sha = repo.sha(parent)
            raise "unknown re: #{parent.inspect}"
          end
          
          repo.link(sha, update)
        end
      
        # if specified, link the issue to a commit
        if commit = doc['at']
          repo.link(commit, update, :ref => issue)
        end
      
        repo.commit!("update #{update} re #{issue}") if request['commit'] == 'true'
        redirect url("/issue/#{issue}/#{update}")
      end
      
      # Same as document, but ensures each of the INHERIT attributes is
      # inherited from doc if it is not specified in the request.
      def inherit(doc, overrides=nil)
        base = document(overrides)
        INHERIT.each {|key| base[key] ||= doc[key] }
        base
      end
    end
  end
end