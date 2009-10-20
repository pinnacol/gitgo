require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/controller'

class ControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  attr_accessor :app
  
  class Root < Gitgo::Controller
    get("/") { "got / in Root" }
    get("/:a/:b") {|a,b| "got /#{a}/#{b} in Root" }
    get("/*") {|splat| "got *#{splat} in Root" }
  end
  
  def test_controllers_set_normal_routes_in_subclasses
    @app = Root
    
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
  
  class Nest < Gitgo::Controller
    set :resource_name, "nest"
    
    get("/") { "got / in Nest" }
    get("/:a/:b") {|a,b| "got /#{a}/#{b} in Nest" }
    get("/*") {|splat| "got *#{splat} in Nest" }
  end
  
  def test_controllers_nest_routes_when_name_is_set
    @app = Nest
    
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
    assert_equal nil, Root.resource_name
    assert_equal "nest", Nest.resource_name
  end
end