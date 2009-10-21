require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/server'

class ServerUtilsTest < Test::Unit::TestCase
  include Gitgo::Server::Utils
  
  def test_path_links
    assert_equal [
      "<a href=\"/tree/id\">id</a>",
      "<a href=\"/tree/id/path\">path</a>",
      "<a href=\"/tree/id/path/to\">to</a>",
      "obj"
    ], path_links("id", "path/to/obj")
    
    assert_equal [
      "<a href=\"/tree/id\">id</a>"
    ], path_links("id", "")
  end
end

class ServerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  def app
    Gitgo::Server
  end
  
  def setup_app(repo)
    repo = Gitgo::Repo.new(setup_repo(repo))
    app.instance_variable_set :@prototype, app.new(nil, repo)
  end
  
  #
  # tree test
  #
  
  def test_default_commit_is_master
    setup_app("simple.git")
    
    get("/tree/master")
    assert last_response.ok?
    master_response = last_response
  
    get("/tree")
    assert last_response.ok?
    assert_equal master_response.body, last_response.body
  end
  
  def test_get_tree_shows_linked_tree_contents_for_commit
    setup_app("simple.git")
    
    # by ref
    get("/tree/xyz")
    assert last_response.body.include?('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert last_response.body.include?('added files x, y, and z')
    %w{
      /blob/xyz/a.txt
      /tree/xyz/a
      /blob/xyz/one.txt
      /tree/xyz/one
      /blob/xyz/x.txt
      /tree/xyz/x
    }.each do |link|
      assert last_response.body.include?(link)
    end
    
    # by sha
    get("/tree/7d3db1d8b487a098e9f5bca17c21c668d800f749/a")
    assert last_response.body.include?('7d3db1d8b487a098e9f5bca17c21c668d800f749')
    assert last_response.body.include?('changed contents of a, b, and c')
    %w{
      /blob/7d3db1d8b487a098e9f5bca17c21c668d800f749/a/b.txt
      /tree/7d3db1d8b487a098e9f5bca17c21c668d800f749/a/b
    }.each do |link|
      assert last_response.body.include?(link)
    end
    
    # by tag
    get("/tree/only-123/one/two")
    assert last_response.body.include?('449b5502e8dc49264d862b4fc0c01ba115fc9f82')
    assert last_response.body.include?('removed files a, b, and c')
    %w{
      /blob/only-123/one/two/three.txt
    }.each do |link|
      assert last_response.body.include?(link)
    end
  end
  
  #
  # blob test
  #
  
  def test_get_blob_shows_contents_for_blob
    setup_app("simple.git")
    
    # by ref
    get("/blob/xyz/x.txt")
    assert last_response.body.include?('ee9a1ca4441ab2bf937808b26eab784f3d041643')
    assert last_response.body.include?('added files x, y, and z')
    assert last_response.body.include?('Contents of file x.')
    
    # by sha
    get("/blob/7d3db1d8b487a098e9f5bca17c21c668d800f749/a/b.txt")
    assert last_response.body.include?('7d3db1d8b487a098e9f5bca17c21c668d800f749')
    assert last_response.body.include?('changed contents of a, b, and c')
    assert last_response.body.include?('Contents of file B.')

    # by tag
    get("/blob/only-123/one/two/three.txt")
    assert last_response.body.include?('449b5502e8dc49264d862b4fc0c01ba115fc9f82')
    assert last_response.body.include?('removed files a, b, and c')
    assert last_response.body.include?('Contents of file three.')
  end
end