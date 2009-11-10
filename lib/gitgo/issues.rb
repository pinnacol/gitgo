require 'gitgo/controller'
require 'gitgo/index'

module Gitgo
  class Issues < Controller
    set :resource_name, "issue"
    set :views, "views/issues"

    get('/')       { index }
    get('/:id')    {|id| show(id) }
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
    INDEX = "iss"
    INHERIT = %w{state tags}
    STATES = %w{open closed}
    
    def index
      state = request['state']
      issues = idx.query(state) do
        idx.select_keys do |id|
          state.nil? || docs[id]['state'] == state
        end.collect do |id|
          docs[id]
        end
      end
      
      erb :index, :locals => {
        :issues => issues,
        :current_state => state
      }
    end
    
    def create
      issue = repo.create(content, attrs.merge!('state' => 'open'))
      repo.link(issue, issue, :dir => INDEX)
      idx.update(issue)
      
      # if specified, link the issue to an object (should be a commit)
      if commit = at_commit
        repo.link(commit, issue, :ref => issue)
      end
      
      repo.commit!("added issue #{issue}") if commit?
      redirect url(issue)
    end
    
    def show(issue)
      children = {}
      active = idx[issue]
      
      # get children and resolve to docs
      repo.children(issue, :recursive => true).each_key do |id|
        doc = docs[id]
        doc[:active] = active.include?(doc)
      end.each_pair do |parent_id, child_ids|
        parent_doc = docs[parent_id]
        child_docs = child_ids.collect {|id| docs[id] }
        children[parent_doc] = child_docs
      end
      
      erb :show, :locals => {
        :id => issue,
        :doc => docs[issue],
        :children => children
      }
    end
    
    # Update adds a comment to the specified issue.
    def update(issue)
      unless doc = docs[issue]
        raise "unknown issue: #{issue.inspect}"
      end
      
      comment = repo.create(content, inherit(doc))
      repo.link(issue, comment, :dir => INDEX)
      idx.update(issue)
      
      # link the comment to each parent and update the index
      parents = request[REGARDING] || [issue]
      parents = [parents] unless parents.kind_of?(Array)
      
      parents.each do |parent|
        repo.unlink(issue, parent, :dir => INDEX)
        repo.link(parent, comment)
      end
      
      # if specified, link the issue to an object (should be a commit)
      if commit = at_commit
        repo.link(commit, comment, :ref => issue)
      end
      
      repo.commit!("updated issue #{issue}") if commit?
      redirect url(issue)
    end
    
    def destroy(issue)
      # repo.children(issue, :recursive => true)
      #   repo.unlink(parent, child, :recursive => recursive?)
      # end
      # 
      # if doc = repo.destroy(issue)
      #   repo.commit("removed document: #{child}") if commit?
      # end
      # 
      # redirect(request['redirect'] || url)
      # 
      # doc = repo.read(issue)
      # comment = repo.create(request[CONTENT], inherit(doc))
      # 
      # # if re is specified, link the comment to the object (should be a commit)
      # # as an update to the issue... ie using a blob that points to the issue.
      # if commit = request[REGARDING]
      #   repo.link(commit, comment, :as => issue)
      # end
      # 
      # repo.commit("updated issue #{issue}") if commit?
      # redirect url(issue)
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
    def inherit(doc)
      base = attrs
      INHERIT.each {|key| base[key] ||= doc[key] }
      base
    end
    
    # A self-filling per-request cache of documents that ensures a document will
    # only be read once within a given request.  Use like:
    #
    #   doc = docs[id]
    #
    def docs
      @docs ||= Hash.new {|hash, id| hash[id] = repo.read(id) }
    end
    
    def idx
      @idx ||= begin
        idx = Index.new do |issue|
          repo.children(issue, :dir => INDEX)
        end
        
        # tree = repo.tree[INDEX]
        # tree.each_tree do |ab, ab_tree|
        #   ab_tree.each_tree do |xyz, xyz_tree|
        #     idx.update "#{ab}#{xyz}"
        #   end
        # end if tree
        
        idx
      end
    end
    
    def issues
      idx.keys
    end
    
    def refs
      grit.refs
    end
    
    def states
      idx.query(:states) do
        doc_states = idx.collect {|id| docs[id]['state'] }.compact
        (STATES + doc_states).uniq.sort
      end
    end
    
    def tags
      idx.query(:tags) do
        idx.collect {|id| docs[id]['tags'] }.compact.flatten.uniq.sort
      end
    end
  end
end