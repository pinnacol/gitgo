require 'gitgo/controller'
require 'gitgo/documents/comment'

module Gitgo
  module Controllers
    class Code < Controller
      set :views, File.expand_path("views/code", ROOT)
      
      get('/code')            { index }
      get('/blob')            { blob_grep }
      get('/tree')            { tree_grep }
      get('/commit')          { commit_grep }

      get('/blob/:treeish/*')  {|treeish, path| show_blob(treeish, path) }
      get('/tree/:treeish')    {|treeish| show_tree(treeish, '') }
      get('/tree/:treeish/*')  {|treeish, path| show_tree(treeish, path) }
      get('/commit/:treeish')  {|treeish| show_commit(treeish) }
      get('/commits/:treeish') {|treeish| show_commits(treeish) }
      get('/obj/:sha')         {|sha| show_object(sha) }

      get('/comment/:sha')     {|sha| read(sha) }
      post('/comment')         { create }
      post('/comment/:sha') do |sha|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(obj)
        when /\Adelete\z/i then destroy(obj)
        else raise("unknown post method: #{_method}")
        end
      end
      put('/comment/:sha')     {|sha| update(sha) }
      delete('/comment/:sha')  {|sha| destroy(sha) }
      
      Comment = Documents::Comment
      
      #
      # actions
      #
      
      def index
        erb :index, :locals => {
          :branches => grit.branches,
          :tags => grit.tags
        }
      end
      
      def treeish
        request['at'] || grit.head.commit
      end
      
      def grep_opts(overrides={})
        {
          :ignore_case   => request['ignore_case'] == 'true',
          :invert_match  => request['invert_match'] == 'true',
          :fixed_strings => request['fixed_strings'] == 'true',
        }.merge!(overrides)
      end
      
      def blob_grep
        options = grep_opts(:e => request['pattern'])
        
        selected = []
        git.grep(options, treeish) do |path, blob|
          selected << [path, blob.id]
        end

        erb :grep, :locals => options.merge!(
          :type => 'blob',
          :at => treeish,
          :selected => selected
        )
      end

      def tree_grep
        options = grep_opts(:e => request['pattern'])
        
        selected = []
        git.tree_grep(options, treeish) do |path, blob|
          selected << [path, blob.id]
        end
        
        erb :grep, :locals => options.merge!(
          :type => 'tree',
          :at => treeish,
          :selected => selected
        )
      end

      def commit_grep
        options = grep_opts(
          :author => request['author'],
          :committer => request['committer'],
          :grep => request['grep'],
          :regexp_ignore_case => request['regexp_ignore_case'] == 'true',
          :fixed_strings => request['fixed_strings'] == 'true',
          :all_match => request['all_match'] == 'true',
          :max_count => request['max_count'] || '10'
        )
        
        selected = []
        git.commit_grep(options, treeish) {|sha| selected << sha }
        
        erb :commit_grep, :locals => options.merge!(
          :selected => selected
        )
      end

      def show_blob(treeish, path)
        commit = grit.commit(treeish) || not_found
        blob = commit.tree / path || not_found

        erb :blob, :locals => {
          :commit => commit, 
          :treeish => treeish, 
          :blob => blob, 
          :path => path
        }
      end

      def show_tree(treeish, path)
        commit = grit.commit(treeish) || not_found
        tree = path.split("/").inject(commit.tree) do |obj, name|
          not_found if obj.nil?
          obj.trees.find {|obj| obj.name == name }
        end

        erb :tree, :locals => {
          :commit => commit, 
          :treeish => treeish, 
          :tree => tree, 
          :path => path
        }
      end
      
      def show_commit(treeish)
        commit = grit.commit(treeish) || not_found
        erb :diff, :locals => {
          :commit => commit, 
          :treeish => treeish
        }
      end
      
      def show_commits(treeish)
        commit = grit.commit(treeish)
        page = (request[:page] || 0).to_i
        per_page = (request[:per_page] || 10).to_i

        erb :commits, :locals => {
          :treeish => treeish,
          :page => page,
          :per_page => per_page,
          :commits => grit.commits(commit.sha, per_page, page * per_page)
        }
      end
      
      def show_object(sha)
        sha = git.resolve(sha)
        
        case
        when request['content'] == 'true'
          response['Content-Type'] = 'text/plain'
          grit.git.cat_file({:p => true}, sha)
          
        when request['download'] == 'true'
          response['Content-Type'] = 'text/plain'
          response['Content-Disposition'] = "attachment; filename=#{sha};"
          raw_object = grit.git.ruby_git.get_raw_object_by_sha1(sha)
          "%s %d\0" % [raw_object.type, raw_object.content.length] + raw_object.content
          
        else
          type = git.type(sha).to_sym
          obj = git.get(type, sha) or not_found
          
          erb type, :locals => {
            :sha => sha, 
            :obj => obj
          }, :views => path('views/code/obj')
        end
      end
      
      def create
        comment = Comment.create(request['doc'])
        repo.commit! if request['commit']
        redirect_to_origin(comment)
      end
    
      def update(sha)
        comment = Comment.update(sha, request['doc'])
        repo.commit! if request['commit']
        redirect_to_origin(comment)
      end

      def destroy(sha)
        comment = Comment.delete(sha)
        repo.commit! if request['commit']
        redirect_to_origin(comment)
      end
      
      def render_comments(sha)
        # comments = comment.tree(sha)
        # 
        # if comments.empty?
        #   erb(:_comment_form, :locals => {:sha => sha, :parent => nil}, :layout => false)
        # else
        #   erb(:_comments, :locals => {:comments => comments}, :layout => false)
        # end
      end
    end
  end
end