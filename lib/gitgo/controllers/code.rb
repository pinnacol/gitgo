require 'gitgo/controller'

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
      
      #
      # actions
      #
      
      def index
        erb :index, :locals => {
          :branches => grit.branches,
          :tags => grit.tags
        }
      end

      def blob_grep
        options = {
          :ignore_case   => request['ignore_case'] == 'true',
          :invert_match  => request['invert_match'] == 'true',
          :fixed_strings => request['fixed_strings'] == 'true',
          :e => request['pattern']
        }

        unless commit = grit.commit(request['at']) || grit.head.commit
          raise "unknown commit: #{request['at']}"
        end

        selected = []
        unless options[:e].to_s.empty?
          pattern = options.merge(
            :cached => true,
            :name_only => true,
            :full_name => true
          )

          repo.sandbox do |git, work_tree, index_file|
            git.read_tree({:index_output => index_file}, commit.tree.id)
            git.grep(pattern).split("\n").each do |path|
              selected << [path, commit.tree / path]
            end
          end
        end

        erb :grep, :locals => options.merge(
          :type => 'blob',
          :at => commit.sha,
          :selected => selected
        )
      end

      def tree_grep
        options = {
          :ignore_case   => request['ignore_case'] == 'true',
          :invert_match  => request['invert_match'] == 'true',
          :fixed_strings => request['fixed_strings'] == 'true',
        }

        unless commit = grit.commit(request['at']) || grit.head.commit
          raise "unknown commit: #{request['at']}"
        end

        selected = []
        if pattern = request['pattern']
          repo.sandbox do |git, work_tree, index_file|
            postfix = pattern.empty? ? '' : begin
              grep_options = git.transform_options(options)
              " | grep #{grep_options.join(' ')} #{grit.git.e(pattern)}"
            end

            results = git.run('', :ls_tree, postfix, {:name_only => true, :r => true}, [commit.tree.id])
            results.split("\n").each do |path|
              selected << [path, commit.tree / path]
            end
          end
        end

        erb :grep, :locals => options.merge(
          :type => 'tree',
          :at => commit.sha,
          :selected => selected,
          :e => pattern
        )
      end

      def commit_grep
        patterns = {
          :author => request['author'],
          :committer => request['committer'],
          :grep => request['grep']
        }

        filters = {
          :regexp_ignore_case => request['regexp_ignore_case'] == 'true',
          :fixed_strings => request['fixed_strings'] == 'true',
          :all_match => request['all_match'] == 'true',
          :max_count => request['max_count'] || '10'
        }

        options = {}
        patterns.each_pair do |key, value|
          unless value.nil? || value.empty?
            options[key] = value
          end
        end

        selected = []
        unless options.empty?
          options.merge!(filters)
          options[:format] = "%H"

          repo.sandbox do |git, work_tree, index_file|
            git.log(options).split("\n").each do |sha|
              selected << grit.commit(sha)
            end
          end
        end

        locals = {:selected => selected}.merge!(patterns).merge!(filters)
        erb :commit_grep, :locals => locals
      end

      def show_blob(treeish, path)
        commit = grit.commit(treeish) || not_found
        blob = commit.tree / path || not_found

        erb :blob, :locals => {:commit => commit, :treeish => treeish, :blob => blob, :path => path}
      end

      def show_tree(treeish, path)
        commit = grit.commit(treeish) || not_found
        tree = path.split("/").inject(commit.tree) do |obj, name|
          not_found if obj.nil?
          obj.trees.find {|obj| obj.name == name }
        end

        erb :tree, :locals => {:commit => commit, :treeish => treeish, :tree => tree, :path => path}
      end
      
      def show_commit(treeish)
        commit = grit.commit(treeish) || not_found
        erb :diff, :locals => {:commit => commit, :treeish => treeish}
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
      
      def show_object(shaish)
        unless sha = repo.sha(shaish)
          raise "unknown object: #{shaish}"
        end
        
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
          type = repo.type(sha)
          obj = case type
          when 'blob', 'tree', 'commit'
            grit.send(type, sha)
          when 'tag'
            commit = grit.send('commit', sha)
            grit.tags.find {|tag| tag.commit.tree.id == commit.tree.id }
          else
            nil
          end
          
          if obj.nil?
            not_found
          end
          
          erb type.to_sym, :locals => {:sha => sha, :obj => obj}, :views => path('views/code/obj')
        end
      end
      
      def create
        sha = request['re']
        unless object = repo.sha(sha)
          raise "unknown object: #{sha}"
        end
        
        # determine and validate parents
        parents = request['parents']
        parents = parents ? repo.rev_parse(*parents) : [object]
        parents.each do |parent|
          next if parent == object
          
          parent_doc = cache[parent]
          unless parent_doc && parent_doc['re'] == object
            raise "invalid parent for comment on #{object}: #{parent}"
          end
        end
        
        # create the new comment
        doc = document('type' => 'comment', 're' => object)
        raise 'no content specified' if doc.empty?
        
        comment = repo.store(doc)
        parents.each do |parent|
          repo.link(parent, comment)
        end
        
        repo.commit!("comment #{comment} re #{object}") if request['commit'] == 'true'
        redirect_to(comment)
      end
    
      def update(sha)
        comment, object = comment_and_object_shas(sha)
        
        # update the comment
        doc = document('type' => 'comment', 're' => object)
        raise 'no content specified' if doc.empty?
        new_comment = repo.store(doc)
        
        # reassign links
        ancestry = repo.children(object, :recursive => true)
        
        ancestry.each_pair do |parent, children|
          next unless children.include?(comment)
          
          repo.unlink(parent, comment)
          repo.link(parent, new_comment)
        end
        
        ancestry[comment].each do |child|
          repo.unlink(comment, child)
          repo.link(new_comment, child)
        end
        
        # remove the current comment
        repo.destroy(comment, false)
        
        repo.commit!("update #{comment} with #{new_comment}") if request['commit'] == 'true'
        redirect_to(new_comment)
      end
    
      def destroy(sha)
        comment, object = comment_and_object_shas(sha)
        
        # reassign links to parent, and unassign links
        ancestry = repo.children(object, :recursive => true)
        
        ancestry.each_pair do |parent, children|
          if children.include?(comment)
            repo.unlink(parent, comment)
          
            ancestry[comment].each do |child|
              repo.link(parent, child)
            end
          end
        end
        
        ancestry[comment].each do |child|
          repo.unlink(comment, child)
        end
        
        # remove the comment
        repo.destroy(comment, false)
        
        repo.commit!("remove #{comment}") if request['commit'] == 'true'
        redirect_to(object)
      end
      
      #
      # helpers
      #
      
      def comment_and_object_shas(sha)
        unless comment = cache[sha]
          raise "unknown comment: #{sha}"
        end
        
        unless comment['type'] == 'comment'
          raise "not a comment: #{comment.sha}"
        end
        
        unless object = comment['re']
          raise "invalid comment: #{comment.sha}"
        end
        
        [comment.sha, object]
      end
      
      def render_comments(sha)
        comments = repo.comments(sha, cache)

        if comments.empty?
          erb(:_comment_form, :locals => {:sha => sha, :parent => nil}, :layout => false)
        else
          erb(:_comments, :locals => {:comments => comments}, :layout => false)
        end
      end
      
      def redirect_to(object)
        redirect(request['redirect'] || "obj/#{object}")
      end
    end
  end
end