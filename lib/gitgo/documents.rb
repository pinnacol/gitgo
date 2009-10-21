require 'gitgo/controller'
require 'gitgo/document'

module Gitgo
  class Documents < Controller
    set :resource_name, "doc"
    set :views, "views/documents"

    # Routing
    get('/:id') {|id| show(id) }
    post('/')    { create(request[:id]) }
    post('/:id') do |id|
      _method = request[:_method]
      case _method
      when /\Aupdate\z/i then update(id)
      when /\Adelete\z/i then destroy(id)
      when nil           then create(id)
      else raise("unknown post method: #{_method}")
      end
    end
    put('/:id')    {|id| update(id) }
    delete('/:id') {|id| destroy(id) }
    
    def show(id)
      if blob = grit.blob(id)
        comment = Document.new(blob.data, id)
        erb :comment, :locals => {:comment => comment}
      else
        not_found
      end
    end
  end
end