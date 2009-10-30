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
        idx.select_keys do |doc|
          state.nil? || doc['state'] == state
        end.collect do |id|
          repo.read(id)
        end
      end
      
      erb :index, :locals => {
        :issues => issues,
        :states => states,
        :current_state => state,
        :refs => grit.refs
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
      docs = {}
      children = {}
      active = idx[issue]
      
      repo.children(issue, :recursive => true).each_key do |id|
        doc = repo.read(id)
        doc[:active] = active.include?(doc)
        docs[id] = doc
      end.each_pair do |parent_id, child_ids|
        parent_doc = docs[parent_id]
        child_docs = child_ids.collect {|id| docs[id] }
        children[parent_doc] = child_docs
      end
      
      erb :show, :locals => {
        :doc => docs[issue],
        :children => children
      }
    end
    
    # Update adds a comment to the specified issue.
    def update(issue)
      unless doc = repo.read(issue)
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
    
    def idx
      @idx ||= begin
        idx = Index.new do |issue|
          repo.children(issue, :dir => INDEX).collect do |id|
            repo.read(id)
          end
        end
        
        tree = repo.tree[INDEX]
        tree.each_tree do |ab, ab_tree|
          ab_tree.each_tree do |xyz, xyz_tree|
            idx.update "#{ab}#{xyz}"
          end
        end if tree
        
        idx
      end
    end
    
    def issues
      idx.keys
    end
    
    def states
      idx.query(:states) do
        doc_states = idx.collect {|doc| doc['state'] }.compact
        (STATES + doc_states).uniq.sort
      end
    end
    
    def tags
      idx.query(:tags) do
        idx.collect {|doc| doc['tags'] }.compact.flatten.uniq.sort
      end
    end
  end
end