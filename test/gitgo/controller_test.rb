require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/controller'

class ControllerTest < Test::Unit::TestCase
  Controller = Gitgo::Controller
  
  class MockRequest
    attr_accessor :env
    def initialize(env={})
      @env = env
    end
  end
  
  def app
    @app ||= Controller.new
  end
  
  #
  # initialize test
  #
  
  def test_controllers_use_repo_provided_during_init
    app = Controller.new(nil, :repo)
    assert_equal :repo, app.repo
  end
  
  #
  # url test
  #
  
  def test_url_returns_path
    app.request = MockRequest.new
    
    assert_equal "/", app.url("/")
    assert_equal "/path/to/resource", app.url("/path/to/resource")
  end
  
  def test_url_relative_to_mount_point
    app.request = MockRequest.new(Controller::MOUNT_POINT => '/mount/point')
    
    assert_equal "/mount/point/", app.url("/")
    assert_equal "/mount/point/path/to/resource", app.url("/path/to/resource")
  end
end