Gem::Specification.new do |s|
  s.name = "gitgo"
  s.version = "0.0.1"
  s.author = "Simon Chiang"
  s.email = "simon.chiang@pinnacol.com"
  s.homepage = ""
  s.platform = Gem::Platform::RUBY
  s.summary = "Issues, comments, and a wiki for git projects."
  s.require_path = "lib"
  s.rubyforge_project = "gitgo"
  s.has_rdoc = true
  s.rdoc_options.concat %W{--main README -S -N --title Gitgo}
  
  # add dependencies
  s.add_dependency("sinatra", "= 0.9.4")
  s.add_dependency("RedCloth", "= 4.2.2")
  s.add_dependency("mojombo-grit", "= 1.1.1")
  
  s.add_development_dependency("rack-test", "= 0.3")
  s.add_development_dependency("tap-test", ">= 0.2.0")
  
  # list extra rdoc files here.
  s.extra_rdoc_files = %W{
    History
    README
  }
  
  # list the files you want to include here.
  s.files = %W{
  }
end