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
      id = repo.create(request['content'], attrs('open' => 'true'))
      repo.mark("iss/open", id)
      repo.commit("added issue #{id}") if commit?
      redirect url(id)
    end
    
    def show(id)
      erb :show, :locals => {
        :doc => repo.read(id),
        :opinions => opinions(id)
      }
    end
    
    def update(id)
    end
    
    def destroy(id)
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
    
    def attrs(overrides={})
      attrs = request['doc'] || {}
      attrs['author']  = author
      attrs.merge!(overrides)
      attrs
    end
    
    def commit?
      request['commit'] =~ /\Atrue\z/i ? true : false
    end
  end
end