require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/server'

class ServerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  def app
    Gitgo::Server
  end
  
  def setup_app(repo)
    app.set :repo, Gitgo::Repo.new(setup_repo(repo))
    app.instance_variable_set :@prototype, nil
  end
  
  #
  # commit test
  #
  
  def test_get_commit_shows_diff
    setup_app("simple.git")
    
    get("/commit/e9b525ed0dfde2833001173e7f185939b46b0274")
    assert last_response.ok?
    assert last_response.body.include?('<li class="add">alpha.txt</li>')
    assert last_response.body.include?('<li class="rm">one.txt</li>')
    
    diff = %q{--- a/x.txt
+++ b/x.txt
@@ -1 +1 @@
-Contents of file x.
\ No newline at end of file
+Contents of file X.
\ No newline at end of file}

    assert last_response.body.include?(diff)
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

  #
  # show test
  #

  def test_get_show_shows_object_and_comments
    setup_app("gitgo.git")

    get("/show/11361c0dbe9a65c223ff07f084cceb9c6cf3a043")
    assert last_response.ok?
    assert last_response.body.include?('11361c0dbe9a65c223ff07f084cceb9c6cf3a043')
    assert last_response.body.include?('Issue Two Content')
    assert last_response.body.include?('c1a80236d015d612d6251fca9611847362698e1c')
    assert last_response.body.include?('Issue Two Comment')
    assert last_response.body.include?('0407a96aebf2108e60927545f054a02f20e981ac')
    assert last_response.body.include?('closed')
  end
end