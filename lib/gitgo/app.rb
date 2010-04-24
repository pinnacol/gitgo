require 'gitgo/controller'
require 'gitgo/controllers/code'
require 'gitgo/controllers/issue'
require 'gitgo/controllers/repo'
require 'gitgo/controllers/wiki'

module Gitgo
  class App < Controller
    set :views, File.expand_path("views/app", ROOT)
    set :static, true
    
    before do
      if repo.git.head.nil? && request.get? && request.path_info != '/welcome'
        redirect '/welcome'
      end
    end
    
    get('/')         { timeline }
    get('/timeline') { timeline }
    get('/welcome')  { welcome }
    post('/setup')   { setup }
    
    use Controllers::Code
    use Controllers::Issue
    use Controllers::Wiki
    use Controllers::Repo
    
    def welcome
      git = repo.git
      
      erb :welcome, :locals => {
        :path => git.path,
        :branch => git.branch,
        :remotes => git.grit.remotes
      }
    end
    
    def setup
      git = repo.git
       
      unless git.head.nil?
        raise "#{git.branch} branch already exists"
      end
        
      upstream_branch = request[:upstream_branch]
      unless upstream_branch.nil? || upstream_branch.empty?
        git.track(upstream_branch)
        git.pull(upstream_branch)
        Document.update_index
      end
      
      redirect url('')
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
  end
end