require 'gitgo/controller'

module Gitgo
  module Controllers
    class Issue < Controller
      set :resource_name, "issue"
      set :views, "views/issue"

      get('/')       { index }
      get('/:id')    {|id| show(id) }
      get('/:id/:comment') {|id, comment| show(id, comment) }
      post('/')      { create }
      post('/:id') do |id|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(id)
        when /\Adelete\z/i then destroy(id)
        else raise("unknown post method: #{_method}")
        end
      end
      put('/:id')    {|id| update(id) }
      delete('/:id') {|id| destroy(id) }
    
      COMMIT = "at"
      REGARDING = "re"
      INHERIT = %w{state tags}
      STATES = %w{open closed}
    
      def index
        issues = self.issues
      
        criteria = {}
        request.params.each_pair do |key, values|
          criteria[key] = values.kind_of?(Array) ? values : [values]
        end
      
        filters = []
        criteria.each_pair do |key, values|
          filter = values.collect do |value|
            repo.index(key, value)
          end.flatten
        
          filters << filter
        end
      
        unless filters.empty?
          issues.delete_if do |issue|
            selected = repo.tails(issue)
            filters.each do |filter|
              selected = selected & filter
            end
          
            selected.empty?
          end
        end
      
        issues.collect! {|sha| docs[sha] }
      
        erb :index, :locals => {
          :issues => issues,
          :criteria => criteria
        }
      end
    
      def create
        issue = repo.create(content, attrs('type' => 'issue', 'state' => 'open'))
      
        # if specified, link the issue to an object (should be a commit)
        if commit = at_commit
          repo.link(commit, issue, :ref => issue)
        end
      
        repo.commit!("added issue #{issue}") if commit?
        redirect url(issue)
      end
    
      def show(issue, comment=nil)
        unless issue_doc = docs[issue]
          raise "unknown issue: #{issue.inspect}"
        end
      
        # get children and resolve to docs
        comments = repo.comments(issue, docs)
        tails = comments.select {|doc| doc[:tail] }
        
        merge_state = 'closed'
        merge_tags = []
        tails.each do |doc|
          # state = tail.state if 
          merge_tags.concat doc.tags
        end
        merge_tags.uniq!
      
        erb :show, :locals => {
          :id => issue,
          :doc => issue_doc,
          :comments => comments,
          :tails => tails,
          :merge_tags => merge_state,
          :merge_tags => merge_tags,
          :selected => comment,
        }
      end
    
      # Update adds a comment to the specified issue.
      def update(issue)
        unless doc = docs[issue]
          raise "unknown issue: #{issue.inspect}"
        end
      
        # note the comment is always in regards to the issue internally, but it
        # will be linked to comments as specified by the REGARDING parameter
        comment = repo.create(content, inherit(doc, 'type' => 'comment', 're' => issue))

        # link the comment to each parent and update the index
        parents = request[REGARDING] || [issue]
        parents = [parents] unless parents.kind_of?(Array)
        parents.each {|parent| repo.link(parent, comment) }
      
        # if specified, link the issue to an object (should be a commit)
        if commit = at_commit
          repo.link(commit, comment, :ref => issue)
        end
      
        repo.commit!("updated issue #{issue}") if commit?
        redirect url("#{issue}/#{comment}")
      end
    
      #
      # helpers
      #
    
      def at_commit
        commit = request[COMMIT]
        commit && !commit.empty? ? commit : nil
      end
    
      # Same as attrs, but ensures each of the INHERIT attributes is inherited
      # from doc if it is not specified in the request.
      def inherit(doc, overrides=nil)
        base = attrs(overrides)
        INHERIT.each {|key| base[key] ||= doc[key] }
        base
      end
    
      def refs
        grit.refs
      end
    
      # Returns an array of issues
      def issues
        repo.index("type", "issue")
      end
    
      # Returns an array of states currently in use
      def states
        (STATES + repo.list("states")).uniq
      end
    
      # Returns an array of tags currently in use
      def tags
        repo.list("tags")
      end
    end
  end
end