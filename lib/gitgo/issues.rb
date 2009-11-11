require 'gitgo/controller'

module Gitgo
  class Issues < Controller
    set :resource_name, "issue"
    set :views, "views/issues"

    get('/')       { index }
    get('/:id')    {|id| show(id) }
    get('/:id/:comment')    {|id| show(id, comment) }
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
      
      if state = request['state']
        docs_in_state = repo.index("state", state)
        issues.delete_if do |issue|
          (opinions(issue) & docs_in_state).empty?
        end
      end
      
      issues.collect! {|sha| docs[sha] }
      
      erb :index, :locals => {
        :issues => issues,
        :current_state => state
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
      unless docs[issue]
        raise "unknown issue: #{issue.inspect}"
      end
      
      # get children and resolve to docs
      trace = {}
      children(issue).each_key do |id|
        doc = docs[id]
        doc[:active] ||= active?(doc)
      end.each_pair do |parent_id, child_ids|
        parent_doc = docs[parent_id]
        child_docs = child_ids.collect {|id| docs[id] }
        trace[parent_doc] = child_docs
      end
      
      erb :show, :locals => {
        :id => issue,
        :doc => docs[issue],
        :children => trace,
        :comment => comment
      }
    end
    
    # Update adds a comment to the specified issue.
    def update(issue)
      unless doc = docs[issue]
        raise "unknown issue: #{issue.inspect}"
      end
      
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
    
    # Returns an array of children for the issue; cached per-request
    def children(issue)
      repo.children(issue, :recursive => true)
    end
    
    def opinions(issue)
      opinions = []
      children(issue).each_pair do |key, value|
        opinions << key if value.empty?
      end
      opinions
    end
    
    def active?(doc)
      true  # for now...
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