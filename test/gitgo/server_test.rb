require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/server'

class ServerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.new(setup_repo("simple.git"))
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Server
  end
  
  #
  # timeline test
  #
  
  def test_timeline_shows_latest_activity
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    assert last_response.redirect?
    issue = File.basename(last_response['Location'])
    
    post("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "New comment", "commit" => "true")
    assert last_response.redirect?
    comment = File.basename(last_response['Location'])
    
    post("/comments/ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "Comment on a comment", "parent" => comment, "commit" => "true")
    assert last_response.redirect?
    
    put("/issue/#{issue}", "content" => "Comment on the Issue", "commit" => "true")
    assert last_response.redirect? 

    get("/timeline")
    
    assert last_response.body =~ /#{issue}.*ee9a1ca4441ab2bf937808b26eab784f3d041643.*ee9a1ca4441ab2bf937808b26eab784f3d041643.*#{issue}/m
    assert last_response.body =~ /update.*comment.*comment.*issue/m
  end
end