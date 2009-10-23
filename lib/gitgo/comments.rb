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
        :timeline => latest(per_page, page * per_page)
      }
    end
    
    def index(id)
      redirect("/doc/#{id}")
    end
    
    def create(parent)
      id = repo.write("blob", Document.new(request_attributes).to_s)
      repo.link(parent, id) if parent
      
      repo.commit("added document #{id}") if commit?
      response["Sha"] = id
      
      redirect(request['redirect'] || url)
    end
    
    def update(parent, child)
      if doc = repo.doc(child)
        links = repo.links(child)
        repo.unlink(parent, child, :recursive => true) if parent
        
        id = repo.write("blob", doc.merge(request_attributes).to_s)
        
        repo.link(parent, id) if parent
        links.each {|link| repo.link(id, link) }
        
        repo.commit("updated document #{child} to #{id}") if commit?
        response["Sha"] = id
        
        redirect(request['redirect'] || url)
      else
        raise("unknown document: #{child}")
      end
    end
    
    def destroy(parent, child)
      if doc = repo.doc(child)
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
    
    def request_attributes
      attributes = request['attributes'] || {}
      attributes.merge!(
        'author' => user,
        'date' => Time.now,
        'content' => request['content']
      )
      attributes
    end
    
  end
end