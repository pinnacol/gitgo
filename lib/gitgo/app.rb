require 'gitgo/controller'
require 'gitgo/controllers/code'
require 'gitgo/controllers/issue'
require 'gitgo/controllers/repo'
require 'gitgo/controllers/wiki'

module Gitgo
  class App < Controller
    set :views, File.expand_path("views/app", ROOT)
    set :static, true
    
    get('/')         { repo.head ? index : welcome }
    get('/timeline') { timeline }
    
    use Controllers::Code
    use Controllers::Issue
    use Controllers::Wiki
    use Controllers::Repo
    
    def index
      erb :index
    end
    
    def welcome
      erb :welcome, :locals => {
        :branch => repo.branch,
        :remotes => repo.refs
      }
    end
    
    def timeline
      Document.update_index
      
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 5).to_i
      
      author = request[:author]
      author = '' if author == 'unknown'
      
      docs = repo.timeline(:n => per_page, :offset => page * per_page) do |sha|
        author.nil? || repo[sha]['author'].include?("<#{author}>")
      end.collect do |sha|
        Document.cast(repo[sha], sha)
      end.sort_by do |doc|
        doc.date
      end
      
      erb :timeline, :locals => {
        :page => page,
        :per_page => per_page,
        :docs => docs,
        :author => author,
        :authors => repo.index.values('email'),
        :active_sha => session_head
      }
    end
    
    def build_query(params)
      params.delete_if {|key, value| value.nil? }
      super(params)
    end
  end
end