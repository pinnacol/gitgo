require 'gitgo/controller'
require 'gitgo/controllers/code'
require 'gitgo/controllers/issue'
require 'gitgo/controllers/repo'
require 'gitgo/controllers/wiki'

module Gitgo
  class App < Controller
    set :views, File.expand_path("views/app", ROOT)
    set :static, true
    
    get('/')         { repo.head.nil? ? welcome : timeline }
    get('/timeline') { timeline }
    get('/welcome')  { welcome }
    
    post('/setup')   { setup }
    
    use Controllers::Code
    use Controllers::Issue
    use Controllers::Wiki
    use Controllers::Repo
    
    def welcome
      erb :welcome, :locals => {
        :path => git.path,
        :branch => git.branch
      }
    end
    
    def setup
      unless repo.head.nil?
        raise "#{git.branch} branch already exists"
      end
        
      remote = request['remote']
      
      unless remote.empty?
        git.track(remote)
        git.pull(remote)
        Document.update_idx
      end
      
      redirect url('')
    end
    
    def timeline
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 5).to_i
      
      author = request[:author].to_s
      timeline = repo.timeline(:n => per_page, :offset => page * per_page) do |sha|
        author.empty? || repo[sha]['author'].include?("<#{author}>")
      end.collect do |sha|
        Document.cast(repo[sha], sha)
      end.sort_by do |doc|
        doc.date
      end
      
      erb :timeline, :locals => {
        :page => page,
        :per_page => per_page,
        :author => author,
        :timeline => timeline,
        :authors => repo.idx.all('author')
      }
    end
  end
end