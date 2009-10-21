require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/controller'

class ControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  class Controller < Gitgo::Controller
    get("/") { "got / in Root" }
    get("/:a/:b") {|a,b| "got /#{a}/#{b} in Root" }
    get("/*") {|splat| "got *#{splat} in Root" }
  end
  
  def setup
    super
    
    # set prototype to nil to ensure there is no memory
    app.instance_variable_set :@prototype, nil
    @instance = nil
  end
  
  def app
    Controller
  end
  
  def instance
    @instance ||= app.prototype
  end
  
  def test_controllers_set_normal_routes_in_subclasses
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
    assert_equal "/", instance.url("/")
    assert_equal "/path/to/resource", instance.url("/path/to/resource")
    
    assert_equal "", instance.url("")
    assert_equal "path/to/resource", instance.url("path/to/resource")
  end
  
  #
  # user test
  #
  
  def test_user_returns_class_user
    app.set :repo, Gitgo::Repo.new(setup_repo("gitgo.git"))
    app.set :user, Grit::Actor.new("John Doe", "john.doe@example.com")
    
    assert_equal "John Doe", instance.user.name
    assert_equal "john.doe@example.com", instance.user.email
  end
  
  def test_user_reads_user_from_git_if_no_user_is_specified
    app.set :repo, Gitgo::Repo.new(setup_repo("gitgo.git"))
    app.set :user, nil
    
    assert_equal "User One", instance.user.name
    assert_equal "user.one@email.com", instance.user.email
  end
  
  def test_user_returns_user_in_session_over_class_user
    app.set :repo, Gitgo::Repo.new(setup_repo("gitgo.git"))
    app.set :user, Grit::Actor.new("John Doe", "john.doe@example.com")
    
    env = Rack::MockRequest.env_for
    env['rack.session'] = {'user' => "Jane Doe <jane.doe@example.com>"}
    instance.request = Rack::Request.new(env)
    
    assert_equal "Jane Doe", instance.user.name
    assert_equal "jane.doe@example.com", instance.user.email
  end
end
  
class ControllerResourceTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  class NestController < Gitgo::Controller
    set :resource_name, "nest"
    
    get("/") { "got / in Nest" }
    get("/:a/:b") {|a,b| "got /#{a}/#{b} in Nest" }
    get("/*") {|splat| "got *#{splat} in Nest" }
  end
  
  def setup
    super
    @instance = nil
  end
  
  def app
    NestController
  end
  
  def instance
    @instance ||= app.prototype
  end
  
  def test_controllers_nest_routes_when_resource_name_is_set
    get "/"
    assert !last_response.ok?

    get "/nest"
    assert last_response.ok?
    assert_equal "got / in Nest", last_response.body
    
    get "/nest/"
    assert last_response.ok?
    assert_equal "got / in Nest", last_response.body
    
    get "/nest/one/two"
    assert last_response.ok?
    assert_equal "got /one/two in Nest", last_response.body
    
    get "/nest/one/two/three/four"
    assert last_response.ok?
    assert_equal "got *one/two/three/four in Nest", last_response.body
  end
  
  def test_class_variables_do_not_filter_up
    assert_equal nil, Gitgo::Controller.resource_name
    assert_equal "nest", NestController.resource_name
  end
  
  #
  # url test
  #
  
  def test_url_nests_paths
    assert_equal "/nest", instance.url("/")
    assert_equal "/nest/path/to/resource", instance.url("/path/to/resource")
    
    assert_equal "/nest", instance.url("")
    assert_equal "/nest/path/to/resource", instance.url("path/to/resource")
  end
  
end