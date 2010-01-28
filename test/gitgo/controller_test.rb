require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/controller'

class ControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  Controller = Gitgo::Controller
  
  attr_accessor :app
  
  def setup_app(repo=nil)
    @app = Controller.new(nil, repo)
  end
  
  #
  # subclass test
  #
  
  class SubClass < Controller
    get("/") { "got / in Root" }
    get("/:a/:b") {|a,b| "got /#{a}/#{b} in Root" }
    get("/*") {|splat| "got *#{splat} in Root" }
  end
  
  def test_controllers_set_normal_routes_in_subclasses
    @app = SubClass.new
    
    get "/"
    assert last_response.ok?
    assert_equal "got / in Root", last_response.body
    
    get "/one/two"
    assert last_response.ok?
    assert_equal "got /one/two in Root", last_response.body
    
    get "/one/two/three/four"
    assert last_response.ok?
    assert_equal "got *one/two/three/four in Root", last_response.body
  end
  
  #
  # url test
  #
  
  def test_url_returns_path
    setup_app
    app.extend SetMountPoint
    app.mount_point = '/'
    
    assert_equal "/", app.url("/")
    assert_equal "/path/to/resource", app.url("/path/to/resource")
  end
  
  module SetMountPoint
    attr_writer :mount_point
  end
  
  def test_url_relative_to_mount_point
    setup_app
    app.extend SetMountPoint
    app.mount_point = '/mount/point'
    
    assert_equal "/mount/point/", app.url("/")
    assert_equal "/mount/point/path/to/resource", app.url("/path/to/resource")
  end
  
  
  #
  # author test
  #
  
  def test_author_returns_repo_author
    author = Grit::Actor.new("John Doe", "john.doe@example.com")
    repo = Gitgo::Repo.new(setup_repo("gitgo.git"), :author => author)
    setup_app(repo)

    assert_equal repo.author, app.author
  end
end