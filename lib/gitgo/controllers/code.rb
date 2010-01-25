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

      get('/obj/:sha')         {|sha| show_object(sha) }
      get('/commits/:treeish') {|treeish| show_commits(treeish) }
      
      post('/comments/:obj')            {|obj| create(obj) }
      post('/comments/:obj/:comment') do |obj, comment|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(obj, comment)
        when /\Adelete\z/i then destroy(obj, comment)
        else create(obj, comment)
        end
      end
      put('/comments/:obj/:comment')    {|obj, comment| update(obj, comment) }
      delete('/comments/:obj/:comment') {|obj, comment| destroy(obj, comment) }
      
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
      
      def show_object(sha)
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
          when 'blob', 'tree', 'commit' # tag
            grit.send(type, sha)
          else
            not_found
          end
          
          erb type.to_sym, :locals => {:sha => sha, :obj => obj}, :views => path('views/code/obj')
        end
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
      
      def create(obj, parent=obj)
        # determine and validate comment parent
        if parent != obj
          parent_doc = repo.read(parent)
          unless parent_doc && parent_doc['re'] == obj
            raise "invalid parent for comment on #{obj}: #{parent}"
          end
        end
        
        # create the new comment
        doc = document('type' => 'comment', 're' => obj)
        raise 'no content specified' if doc.empty?
        
        comment = repo.store(doc)
        repo.link(parent, comment)
        
        repo.commit("comment #{comment} re #{obj}") if request['commit'] == 'true'
        redirect_to(comment)
      end
    
      def update(obj, comment)
        check_valid_comment(obj, comment)
        
        # update the comment
        doc = document('type' => 'comment', 're' => obj)
        raise 'no content specified' if doc.empty?
        
        new_comment = repo.store(doc)
        
        # reassign links
        ancestry = repo.children(obj, :recursive => true)
        
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
        
        repo.commit("update #{comment} with #{new_comment}") if request['commit'] == 'true'
        redirect_to(new_comment)
      end
    
      def destroy(obj, comment)
        check_valid_comment(obj, comment)
        
        # reassign children to comment parent
        ancestry = repo.children(obj, :recursive => true)
        ancestry.each_pair do |parent, children|
          if children.include?(comment)
            repo.unlink(parent, comment)
          
            ancestry[comment].each do |child|
              repo.link(parent, child)
            end
          end
        end
        
        # unlink children
        ancestry[comment].each do |child|
          repo.unlink(comment, child)
        end
        
        # remove the comment
        repo.destroy(comment, false)
        
        repo.commit("remove #{comment}") if request['commit'] == 'true'
        redirect_to(obj)
      end
      
      def check_valid_comment(obj, comment)
        if doc = repo.read(comment)
          unless doc['type'] == 'comment'
            raise "not a comment: #{comment}"
          end
          
          unless doc['re'] == obj
            raise "not a comment on #{obj}: #{comment}"
          end
        else
          raise("unknown comment: #{comment}")
        end
      end
      
      def redirect_to(sha)
        redirect(request['redirect'] || "obj/#{sha}")
      end
    end
  end
end