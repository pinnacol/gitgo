module Gitgo
  module Rest
    def model
      raise NotImplementedError
    end
    
    def attrs
      request['doc'] || {'at' => session_head}
    end
    
    def preview?
      request['preview'] == 'true'
    end
    
    def preview
      doc = model.new(attrs)
      # doc.normalize!
      erb :new, :locals => {:doc => doc}
    end
  
    def create(sha=nil)
      return(sha.nil? ? preview : show(sha)) if preview?
      
      doc = model.save(attrs)
      
      parents = request['parents']
      if parents.nil? || parents.empty?
        doc.create
      else
        parents = [parents] unless parents.kind_of?(Array)
        parents.collect! do |parent|
          model[parent] or raise "invalid parent: #{parent.inspect}"
        end
        doc.link_to(*parents)
      end
      
      doc.commit!
      redirect_to_doc(doc)
    end
    
    def edit(sha)
      unless doc = model.read(sha)
        raise "unknown #{model.type}: #{sha.inspect}"
      end
      
      doc.merge!(attrs)
      erb :edit, :locals => {:doc => doc}
    end
    
    def update(sha)
      return edit(sha) if preview?
      
      doc = model.update(sha, attrs).commit!
      redirect_to_doc(doc)
    end
    
    def show(sha)
      unless doc = model.read(sha)
        raise "unknown #{model.type}: #{sha.inspect}"
      end
      
      new_doc = doc.inherit(attrs)
      # new_doc.normalize!
      
      erb :show, :locals => {
        :doc => doc,
        :new_doc => new_doc,
        :active_sha => session_head
      }
    end
    
    def destroy(sha)
      doc = model.delete(sha).commit!
      
      if doc.graph_head?
        redirect "/#{model.type}"
      else
        redirect_to_doc(doc)
      end
    end
    
    def redirect_to_doc(doc)
      sha = doc.graph_head? ? doc.graph.head : "#{doc.graph.head}##{doc.sha}"
      redirect "/#{model.type}/#{sha}"
    end
  end
end