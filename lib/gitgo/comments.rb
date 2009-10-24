require 'gitgo/controller'

module Gitgo
  class Comments < Controller
    set :resource_name, "comment"
    set :views, "views/comments"

    # No-parent routes
    get('/')       { timeline }
    get('/:id')    {|id| index(id) }
    post('/')      { create(nil) }
    post('/:id') do |id|
      _method = request[:_method]
      case _method
      when /\Aupdate\z/i then update(nil, id)
      when /\Adelete\z/i then destroy(nil, id)
      when nil           then create(id)
      else raise("unknown post method: #{_method}")
      end
    end
    put('/:id')    {|id| update(nil, id) }
    delete('/:id') {|id| destroy(nil, id) }
    
    # Parent routes
    post('/:parent/:child') do |parent, child|
      _method = request[:_method]
      case _method
      when /\Aupdate\z/i then update(parent, child)
      when /\Adelete\z/i then destroy(parent, child)
      when nil then raise("no post method specified")
      else raise("unknown post method: #{_method}")
      end
    end
    put('/:parent/:child')    {|parent, child| update(parent, child) }
    delete('/:parent/:child') {|parent, child| destroy(parent, child) }
    
    def timeline
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 10).to_i
      
      erb :timeline, :locals => {
        :page => page,
        :per_page => per_page,
        :timeline => repo.timeline(:n => per_page, :offset => page * per_page)
      }
    end
    
    def index(id)
      redirect("/doc/#{id}")
    end
    
    def create(parent)
      id = repo.create(request['content'], request_attributes)
      repo.link(parent, id) if parent
      
      repo.commit("added document #{id}") if commit?
      response["Sha"] = id
      
      redirect(request['redirect'] || url)
    end
    
    def update(parent, child)
      if new_id = repo.update(child, request_attributes(true))
        repo.unlink(parent, child, :recursive => true) if parent
        repo.link(parent, new_id) if parent
        
        repo.commit("updated document #{child} to #{new_id}") if commit?
        response["Sha"] = new_id
        
        redirect(request['redirect'] || url)
      else
        raise("unknown document: #{child}")
      end
    end
    
    def destroy(parent, child)
      if doc = repo.destroy(child)
        repo.unlink(parent, child, :recursive => recursive?) if parent
        repo.commit("removed document: #{child}") if commit?
      end
      
      redirect(request['redirect'] || url)
    end
    
    #
    # helpers
    #
    
    def commit?
      request['commit'] =~ /\Atrue\z/i
    end
    
    def recursive?
      request['recursive'] =~ /\Atrue\z/i
    end
    
    def request_attributes(content=false)
      attributes = request['attributes'] || {}
      attributes.merge!(
        'author' => author,
        'date' => Time.now
      )
      attributes['content'] = request['content'] if content
      attributes
    end
    
  end
end