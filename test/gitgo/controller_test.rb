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
  # author test
  #
  
  def test_author_returns_class_author
    app.set :repo, Gitgo::Repo.new(setup_repo("gitgo.git"))
    app.set :author, Grit::Actor.new("John Doe", "john.doe@example.com")
    
    assert_equal "John Doe", instance.author.name
    assert_equal "john.doe@example.com", instance.author.email
  end
  
  def test_author_reads_author_from_git_if_no_author_is_specified
    app.set :repo, Gitgo::Repo.new(setup_repo("gitgo.git"))
    app.set :author, nil
    
    assert_equal "User One", instance.author.name
    assert_equal "user.one@email.com", instance.author.email
  end
  
  def test_author_returns_author_in_session_over_class_author
    app.set :repo, Gitgo::Repo.new(setup_repo("gitgo.git"))
    app.set :author, Grit::Actor.new("John Doe", "john.doe@example.com")
    
    env = Rack::MockRequest.env_for
    env['rack.session'] = {'author' => "Jane Doe <jane.doe@example.com>"}
    instance.request = Rack::Request.new(env)
    
    assert_equal "Jane Doe", instance.author.name
    assert_equal "jane.doe@example.com", instance.author.email
  end
end