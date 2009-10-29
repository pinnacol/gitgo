require 'gitgo/controller'

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
    INHERIT = %w{state tags}
    STATES = %w{open closed}
    
    def index
      state = request['state'] || 'open'
      erb :index, :locals => {
        :issues => issues(state),
        :states => STATES,
        :current_state => state
      }
    end
    
    def create
      issue = repo.create(content, attrs.merge!('state' => 'open'))
      
      # if specified, link the issue to an object (should be a commit)
      if commit = request[COMMIT]
        repo.link(commit, issue, :ref => issue)
      end
      
      repo.commit("added issue #{issue}") if commit?
      redirect url(issue)
    end
    
    def show(issue)
      erb :show, :locals => {
        :doc => repo.read(issue),
        :opinions => opinions(issue)
      }
    end
    
    # Update adds a comment to the specified issue.
    def update(issue)
      unless doc = repo.read(issue)
        raise "unknown issue: #{issue.inspect}"
      end
      
      comment = repo.create(content, inherit(doc))
      
      # link the comment to each parent
      if parents = request[REGARDING]
        parents = [parents] unless parents.kind_of?(Array)
        parents.each {|parent| repo.link(parent, comment) }
      else
        repo.link(issue, comment)
      end
      
      # if specified, link the issue to an object (should be a commit)
      if commit = request[COMMIT]
        repo.link(commit, comment, :ref => issue)
      end
      
      repo.commit("updated issue #{issue}") if commit?
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
    
    def issues(state)
      issues = repo["iss/#{state}"] || []
      issues.collect {|sha| repo.read(sha) }
    end
    
    def opinions(id)
      repo.children(id, :dir => "iss").collect do |child|
        repo.read(child)
      end
    end
    
    # Same as attrs, but ensures each of the INHERIT attributes is inherited
    # from doc if it is not specified in the request.
    def inherit(doc)
      base = attrs
      INHERIT.each {|key| base[key] ||= doc[key] }
      base
    end  
  end
end