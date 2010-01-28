require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/app'

class AppTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :app
  attr_reader :repo
  attr_reader :server
  
  def setup
    super
    @repo = Gitgo::Repo.new(setup_repo("simple.git"))
    @server = Gitgo::App.new
    
    @app = lambda do |env|
      env['gitgo.repo'] = repo
      server.call(env)
    end
  end
  
  #
  # error test
  #
  
  def test_invalidated_repo_errors_provide_opportunity_to_reset_repo
    server.options.set(:raise_errors, false)
    
    begin
      repo.create("content")
      repo.commit("new commit")
    
      get("/")
      assert last_response.ok?
    
      repo.sandbox {|git,w,i| git.gc }
    
      get("/")
      assert !last_response.ok?
      assert last_response.body.include?('Errno::ENOENT')
      assert last_response.body =~ /No such file or directory - .*idx/
      assert last_response.body.include?('Reset')
    ensure
      server.options.set(:raise_errors, true)
    end
  end
  
  #
  # index test
  #
  
  def test_index_provides_link_to_repo_page_the_repo_branch_doesnt_exist
    assert_equal true, repo.head.nil?
    
    get("/")
    assert last_response.ok? 
    assert last_response.body.include?("setup a #{repo.branch} branch")
    
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    assert_equal false, repo.head.nil?
    
    get("/")
    assert last_response.ok? 
    assert !last_response.body.include?("setup a #{repo.branch} branch")
  end
  
  #
  # timeline test
  #
  
  def test_timeline_shows_latest_activity
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    assert last_response.redirect?
    issue = File.basename(last_response['Location'])
    
    post("/comment", "re" => "ee9a1ca4441ab2bf937808b26eab784f3d041643", "content" => "New comment", "commit" => "true")
    assert last_response.redirect?
    comment = File.basename(last_response['Location'])
    
    post("/comment", "re" => "ee9a1ca4441ab2bf937808b26eab784f3d041643", "parents" => [comment], "content" => "Comment on a comment", "commit" => "true")
    assert last_response.redirect?
    
    put("/issue/#{issue}", "content" => "Comment on the Issue", "commit" => "true")
    assert last_response.redirect? 

    get("/timeline")
    
    assert last_response.body =~ /#{issue}.*ee9a1ca4441ab2bf937808b26eab784f3d041643.*ee9a1ca4441ab2bf937808b26eab784f3d041643.*#{issue}/m
    assert last_response.body =~ /Update.*Comment.*Comment.*Issue/m
  end
  
  def test_timeline_shows_helpful_message_if_no_results_are_available
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    get("/timeline", "page" => 10)
    assert last_response.body.include?('No results to show...')
  end
end