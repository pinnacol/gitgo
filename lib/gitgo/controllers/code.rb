require 'gitgo/controller'

module Gitgo
  module Controllers
    class Code < Controller
      set :views, "views/code"
      
      get("/code")            { index }
      get('/blob')            { blob_grep }
      get('/tree')            { tree_grep }
      get('/commit')          { commit_grep }

      get('/blob/:commit/*')  {|commit, path| show_blob(commit, path) }
      get('/tree/:commit')    {|commit| show_tree(commit) }
      get('/tree/:commit/*')  {|commit, path| show_tree(commit, path) }
      get('/commit/:commit')  {|commit| show_commit(commit) }

      get('/obj/:sha')        {|sha| show_object(sha) }
      get("/commits/:commit") {|commit| show_commits(commit) }
      
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
      
      def index
        erb :index, :locals => {
          :branches => grit.branches,
          :tags => grit.tags
        }
      end

      def blob_grep
        options = {
          :ignore_case => set?("ignore_case"),
          :invert_match => set?("invert_match"),
          :fixed_strings => set?("fixed_strings"),
          :e => request["pattern"]
        }

        id = request["at"] || head.commit
        unless commit = self.commit(id)
          raise "unknown commit: #{id}"
        end

        selected = []
        unless options[:e].to_s.empty?
          pattern = options.merge(
            :cached => true,
            :name_only => true,
            :full_name => true
          )

          repo.sandbox do |work_tree, index_file|
            grit.git.read_tree({:index_output => index_file}, commit.tree.id)
            grit.git.grep(pattern).split("\n").each do |path|
              selected << [path, commit.tree / path]
            end
          end
        end

        erb :grep, :locals => options.merge(
          :type => 'blob',
          :at => id,
          :selected => selected
        )
      end

      def tree_grep
        options = {
          :ignore_case => set?("ignore_case"),
          :invert_match => set?("invert_match"),
          :fixed_strings => set?("fixed_strings"),
        }

        id = request["at"] || head.commit
        unless commit = self.commit(id)
          raise "unknown commit: #{id}"
        end

        pattern = request["pattern"]
        selected = []

        unless pattern.nil?
          repo.sandbox do |work_tree, index_file|
            postfix = pattern.empty? ? '' : begin
              grep_options = grit.git.transform_options(options)
              " | grep #{grep_options.join(' ')} #{grit.git.e(pattern)}"
            end

            results = grit.git.run('', :ls_tree, postfix, {:name_only => true, :r => true}, [commit.tree.id])
            results.split("\n").each do |path|
              selected << [path, commit.tree / path]
            end
          end
        end

        erb :grep, :locals => options.merge(
          :type => 'tree',
          :at => id,
          :selected => selected,
          :e => pattern
        )
      end

      def commit_grep
        patterns = {
          :author => params['author'],
          :committer => params['committer'],
          :grep => params['grep']
        }

        filters = {
          :regexp_ignore_case => set?("regexp_ignore_case"),
          :fixed_strings => set?("fixed_strings"),
          :max_count => params['max_count'] || '10',
          :all_match => set?("all_match")
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

          repo.sandbox do |work_tree, index_file|
            grit.git.log(options).split("\n").each do |sha|
              selected << grit.commit(sha)
            end
          end
        end

        locals = {:selected => selected}.merge!(patterns).merge!(filters)
        erb :commit_grep, :locals => locals
      end

      def show_commit(id)
        commit = self.commit(id) || not_found
        erb :diff, :locals => {:commit => commit}
      end

      def show_tree(id, path="")
        commit = self.commit(id) || not_found
        tree = path.split("/").inject(commit.tree) do |obj, name|
          not_found if obj.nil?
          obj.trees.find {|obj| obj.name == name }
        end

        erb :tree, :locals => {:commit => commit, :id => id, :tree => tree, :path => path}
      end

      def show_blob(id, path)
        commit = self.commit(id)  || not_found
        blob = commit.tree / path || not_found

        erb :blob, :locals => {:commit => commit, :id => id, :blob => blob, :path => path}
      end

      def show_object(id)
        case
        when set?('content')
          response['Content-Type'] = "text/plain"
          grit.git.cat_file({:p => true}, id)

        when set?('download')
          response['Content-Type'] = "text/plain"
          response['Content-Disposition'] = "attachment; filename=#{id};"
          raw_object = grit.git.ruby_git.get_raw_object_by_sha1(id)
          "%s %d\0" % [raw_object.type, raw_object.content.length] + raw_object.content

        else
          type = repo.type(id)
          obj = case type
          when 'blob', 'tree', 'commit' # tag
            grit.send(type, id)
          else
            not_found
          end
          
          erb type.to_sym, :locals => {:id => id, :obj => obj}, :views => 'views/code/obj'
        end
      end
      
      def show_commits(id)
        commit = self.commit(id)
        page = (request[:page] || 0).to_i
        per_page = (request[:per_page] || 10).to_i

        erb :commits, :locals => {
          :id => id,
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
        comment = repo.store(document('type' => 'comment', 're' => obj))
        repo.link(parent, comment)
        
        repo.commit("comment #{comment} re #{obj}") if commit?
        redirect_to(comment)
      end
    
      def update(obj, comment)
        if doc = repo.read(comment)
          unless doc['type'] == 'comment'
            raise "not a comment: #{comment}"
          end
          
          unless doc['re'] == obj
            raise "not a comment on #{obj}: #{comment}"
          end
          
          # update the comment
          new_comment = repo.store(document('type' => 'comment', 're' => obj))
          
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
          
          repo.commit("update #{comment} with #{new_comment}") if commit?
          redirect_to(new_comment)
        else
          raise("unknown comment: #{comment}")
        end
      end
    
      def destroy(obj, comment)
        if repo.destroy(comment, false)
          
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
          
          repo.commit("remove #{comment}") if commit?
          redirect_to(obj)
        else
          raise("unknown comment: #{comment}")
        end
      end
      
      def redirect_to(sha)
        redirect(request['redirect'] || "obj/#{sha}")
      end
      
      def render_comments(id)
         comments = repo.comments(id, docs)
         
         if comments.empty?
           erb(:_comment_form, :locals => {:obj => id, :parent => nil}, :layout => false)
         else
           erb(:_comments, :locals => {:obj => id, :comments => comments}, :layout => false)
         end
       end
      
    end
  end
end