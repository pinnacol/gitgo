require 'gitgo/controller'

module Gitgo
  class Documents < Controller
    set :resource_name, "doc"
    set :views, "views/server"

    # Routing
    get('/')       { index }
    get('/:id')    {|id| show(id) }
    post('/')      { create }
    post('/:id') do |id|
      _method = request[:_method]
      case _method
      when /\Aupdate\z/i then update(id)
      when /\Adelete\z/i then destroy(id)
      when nil then raise("no post method specified")
      else raise("unknown post method: #{_method}")
      end
    end
    put('/:id')    {|id| update(id) }
    delete('/:id') {|id| destroy(id) }
    
    def index
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 10).to_i
      
      erb :timeline, :locals => {
        :page => page,
        :per_page => per_page,
        :timeline => latest(per_page, page * per_page)
      }
    end
    
    def show(id)
      if document = repo.doc(id)
        erb :document, :locals => {:document => document}
      else
        not_found
      end
    end
    
    def create
      raise "no parents or types specified" if parents.empty? && types.empty?
      
      id = repo.write("blob", Document.new(request_attributes).to_s)
      parents.each {|parent| repo.link(parent, id) }
      types.each   {|type| repo.register(type, id) }
      
      if request['commit'] =~ /\Atrue\z/i
        repo.commit("added 1 document")
      end
      
      # request['redirect'] || # back to current page
      redirect url
    end
    
    def update(id)
      if document = repo.doc(id)
        parents.each {|parent| repo.unlink(parent, id) }
        types.each   {|type| repo.unregister(type, id) }
        
        id = repo.write("blob", document.merge(request_attributes))
        
        parents.each {|parent| repo.link(parent, id) }
        types.each   {|type| repo.register(type, id) }
        
        redirect url
      else
        raise("unknown document: #{id}")
      end
    end
    
    def destroy(id)
      if document = repo.doc(id)
        parents.each {|parent| repo.unlink(parent, id) }
        types.each   {|type| repo.unregister(type, id) }
      end
      
      redirect url
    end
    
    #
    # helpers
    #
    
    def parents
      @parents = request['parents'] || []
    end
    
    def types
      @types = request['types'] || []
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