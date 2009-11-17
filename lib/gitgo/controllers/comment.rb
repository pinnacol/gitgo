require 'gitgo/controller'

module Gitgo
  module Controllers
    class Comment < Controller
      set :resource_name, "comment"
      set :views, "views/comment"

      # No-parent routes
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
    
      def index(id)
        redirect("/doc/#{id}")
      end
    
      def create(parent)
        id = repo.store(document)
        repo.link(parent, id) if parent
      
        repo.commit("added document #{id}") if commit?
        response["Sha"] = id
      
        redirect(request['redirect'] || url)
      end
    
      def update(parent, child)
        if doc = repo.update(child, document)
          new_child = doc.sha
          repo.commit("updated document #{child} to #{new_child}") if commit?
          response["Sha"] = new_child
        
          redirect(request['redirect'] || url)
        else
          raise("unknown document: #{child}")
        end
      end
    
      def destroy(parent, child)
        if parent
          repo.unlink(parent, child, :recursive => set?('recursive'))
        end
      
        if doc = repo.destroy(child)
          repo.commit("removed document: #{child}") if commit?
        end
      
        redirect(request['redirect'] || url)
      end
    end
  end
end