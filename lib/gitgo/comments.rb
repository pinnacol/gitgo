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
      doc = Document.new(request_attributes)
      sha = register(doc, parent)
      repo.commit("added document #{sha}") if commit?
      
      redirect url(parent)
    end
    
    def update(parent, child)
      if doc = repo.doc(child)
        unregister(doc, parent)
        doc = doc.merge(request_attributes)
        id = register(doc, parent)
        repo.commit("updated document #{child} to #{id}") if commit?
        
        redirect url
      else
        raise("unknown document: #{child}")
      end
    end
    
    def destroy(parent, child)
      if doc = repo.doc(child)
        unregister(doc, parent)
        repo.commit("removed document: #{child}") if commit?
      end
      
      redirect url
    end
    
    #
    # helpers
    #
    
    def commit?
      request['commit'] =~ /\Atrue\z/i
    end
    
    def register(doc, parent=nil)
      id = repo.write("blob", doc.to_s)
      timestamp = doc.timestamp
      
      if parent
        repo.register(timestamp, parent, :flat => true)
        repo.link(parent, id)
      else
        repo.register(timestamp, id, :flat => true)
      end
      
      response['Sha'] = id
      id
    end
    
    def unregister(doc, parent=nil)
      id = doc.sha
      timestamp = doc.timestamp
      
      if parent
        repo.unlink(parent, id)
        
        # unregister parent from the timestamp unless there
        # is another document created in that timestamp
        others = repo.links(parent) {|sha| sha == id ? nil : repo.doc(sha) }
        others.compact!
        
        unless others.any? {|another| another.timestamp == timestamp }
          repo.unregister(timestamp, parent, :flat => true)
        end
        
      else
        repo.unregister(timestamp, id, :flat => true)
      end
      
      id
    end
    
    def request_attributes
      attributes = request['attributes'] || {}
      attributes.merge!(
        'user' => user,
        'date' => Time.now,
        'content' => request['content']
      )
      attributes
    end
  end
end