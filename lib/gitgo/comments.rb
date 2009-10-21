require 'gitgo/controller'
require 'gitgo/document'

module Gitgo
  class Comments < Controller
    module Utils
      def latest(n=10, offest=0)
        latest = []
        
        years.reverse_each do |year|
          months(year).reverse_each do |month|
            days(year, month).reverse_each do |day|
              
              # y,m,d need to be iterated in reverse to correctly sort by
              # date; this is not the case with the unordered shas
              shas(year, month, day).each do |sha|
                if offest > 0
                  offest -= 1
                else
                  latest << sha
                  return latest if n && latest.length > n
                end
              end
            end
          end
        end
        
        latest
      end

      def years
        repo["/"].select {|dir| dir =~ /\A\d{4}\z/ }.sort
      end

      def months(year)
        repo["/%04d" % year.to_i].sort
      end

      def days(year, month)
        repo["/%04d/%02d" % [year.to_i, month.to_i]].sort
      end

      def shas(year, month, day)
        repo["/%04d/%02d/%02d" % [year.to_i, month.to_i, day.to_i]]
      end
    end
    include Utils
    
    set :resource_name, "comments"
    set :views, "views/comments"

    # Routing
    get('/')     { index }
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
    
    def index
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 10).to_i
      
      erb :index, :locals => {
        :page => page,
        :per_page => per_page,
        :shas => latest(per_page, page * per_page)
      }
    end
    
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