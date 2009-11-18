require 'gitgo/controller'

module Gitgo
  module Controllers
    class Code < Controller
      set :views, "views/code"
      
      get("/code")            { index }
      get('/activity')        { timeline }
      get('/activity/:email') {|email| timeline(email) }

      get('/blob')            { blob_grep }
      get('/tree')            { tree_grep }
      get('/commit')          { commit_grep }

      get('/blob/:commit/*')  {|commit, path| show_blob(commit, path) }
      get('/tree/:commit')    {|commit| show_tree(commit) }
      get('/tree/:commit/*')  {|commit, path| show_tree(commit, path) }
      get('/commit/:commit')  {|commit| show_commit(commit) }

      get('/obj/:sha')        {|sha| show_object(sha) }
      get("/commits/:commit") {|commit| show_commits(commit) }
      
      post('/comment/:child') do |child|
        _method = request[:_method]
        case _method
        when /\Aupdate\z/i then update(nil, child)
        when /\Adelete\z/i then destroy(nil, child)
        else raise("unknown post method: #{_method}")
        end
      end
      put('/comment/:child')      {|child| update(nil, child) }
      delete('/comment/:child')   {|child| destroy(nil, child) }
      
      post('/comments/:parent')            {|parent| create(parent) }
      put('/comments/:parent/:child')      {|parent, child| update(parent, child) }
      delete('/comments/:parent/:child')   {|parent, child| destroy(parent, child) }
      
      def index
        erb :index, :locals => {
          :branches => grit.branches,
          :tags => grit.tags
        }
      end

      def timeline(email=nil)
        page = (request[:page] || 0).to_i
        per_page = (request[:per_page] || 10).to_i

        timeline = repo.timeline(:n => per_page, :offset => page * per_page) do |sha|
          email == nil || docs[sha].author.email == email
        end
        timeline = timeline.collect {|sha| docs[sha] }.sort_by {|doc| doc.date }

        erb :timeline, :locals => {
          :page => page,
          :per_page => per_page,
          :email => email,
          :timeline => timeline,
          :emails => repo.list('author')
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

        erb :tree, :locals => {:commit => commit, :tree => tree, :id => id, :path => path}
      end

      def show_blob(id, path)
        commit = self.commit(id)  || not_found
        blob = commit.tree / path || not_found

        erb :blob, :locals => {:commit => commit, :blob => blob, :id => id, :path => path }
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
          case repo.type(id)
          when "blob"
            erb :blob, :locals => {:id => id, :blob => grit.blob(id)}, :views => "views/obj"
          when "tree"
            erb :tree, :locals => {:id => id, :tree => grit.tree(id)}, :views => "views/obj"
          when "commit"
            erb :commit, :locals => {:id => id, :commit => grit.commit(id)}, :views => "views/obj"
          # when "tag"
          #   erb :tag, :locals => {:id => id, :tag => }, :views => "views/obj"
          else not_found
          end
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
      
      def create(parent)
        id = repo.store(document)
        repo.link(parent, id) if parent
      
        repo.commit("added document #{id}") if commit?
        response["Sha"] = id
      
        redirect(request['redirect'] || url)
      end
    
      def update(parent, child)
        if doc = repo.update(child, document)
          new_child = doc.sha
          repo.commit("updated document #{child} to #{new_child}") if commit?
          response["Sha"] = new_child
        
          redirect(request['redirect'] || url)
        else
          raise("unknown document: #{child}")
        end
      end
    
      def destroy(parent, child)
        if parent
          repo.unlink(parent, child, :recursive => set?('recursive'))
        end
      
        if doc = repo.destroy(child)
          repo.commit("removed document: #{child}") if commit?
        end
      
        redirect(request['redirect'] || url)
      end
    end
  end
end