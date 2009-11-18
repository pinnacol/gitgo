Gem::Specification.new do |s|
  s.name = "gitgo"
  s.version = "0.1.0"
  s.author = "Simon Chiang"
  s.email = "simon.chiang@pinnacol.com"
  s.homepage = ""
  s.platform = Gem::Platform::RUBY
  s.summary = "Issues, comments, and a wiki for git projects."
  s.bindir = "bin"
  s.executables = "gitgo"
  s.require_path = "lib"
  s.rubyforge_project = "gitgo"
  s.has_rdoc = true
  s.rdoc_options.concat %W{--main README -S -N --title Gitgo}
  
  # add dependencies
  s.add_dependency("sinatra", "= 0.9.4")
  s.add_dependency("RedCloth", "= 4.2.2")
  s.add_dependency("grit", "= 2.0.0")
  
  s.add_development_dependency("rack-test", "= 0.3")
  s.add_development_dependency("tap-test", ">= 0.2.0")
  
  # list extra rdoc files here.
  s.extra_rdoc_files = %W{
    History
    README
  }
  
  # list the files you want to include here.
  s.files = %W{
    lib/gitgo/controller.rb
    lib/gitgo/controllers/code.rb
    lib/gitgo/controllers/issue.rb
    lib/gitgo/controllers/repo.rb
    lib/gitgo/controllers/wiki.rb
    lib/gitgo/document.rb
    lib/gitgo/patches/grit.rb
    lib/gitgo/repo.rb
    lib/gitgo/repo/index.rb
    lib/gitgo/repo/tree.rb
    lib/gitgo/repo/utils.rb
    lib/gitgo/server.rb
    lib/gitgo/helpers.rb
    public/css/gitgo.css
    public/javascript/gitgo.js
    public/javascript/jquery-1.3.2.min.js
    public/spec/gitgo_spec.js
    public/spec/jspec.css
    public/spec/jspec.js
    public/tests.html
    views/code/_comment.erb
    views/code/_comment_form.erb
    views/code/_comments.erb
    views/code/_commit.erb
    views/code/_grepnav.erb
    views/code/_treenav.erb
    views/code/_user.erb
    views/code/blob.erb
    views/code/commit_grep.erb
    views/code/commits.erb
    views/code/diff.erb
    views/code/grep.erb
    views/code/index.erb
    views/code/obj/blob.erb
    views/code/obj/commit.erb
    views/code/obj/tag.erb
    views/code/obj/tree.erb
    views/code/tree.erb
    views/error.erb
    views/issue/_at.erb
    views/issue/_comment.erb
    views/issue/_comments.erb
    views/issue/index.erb
    views/issue/show.erb
    views/layout.erb
    views/not_found.erb
    views/repo/design.textile
    views/repo/fsck.erb
    views/repo/idx.erb
    views/repo/index.erb
    views/repo/status.erb
    views/server/timeline.erb
    views/wiki/index.erb
  }
end