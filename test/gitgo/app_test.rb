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
    @repo = Gitgo::Repo.init(setup_repo("simple.git"))
    @server = Gitgo::App.new
    
    @app = lambda do |env|
      env['gitgo.repo'] = repo
      server.call(env)
    end
  end
  
  def git
    repo.git
  end
  
  #
  # setup test
  #
  
  def test_setup_sets_up_tracking_of_specified_remote
    @repo = Gitgo::Repo.new Gitgo::Repo::GIT => git.clone(method_root.path('clone'))
    @app = Gitgo::App.new(nil, repo)
    
    assert_equal nil, git.head
    
    post("/setup", :remote_branch => 'origin/caps')
    assert last_response.redirect?
    assert_equal "/", last_response['Location']
    
    # the caps head
    assert_equal '19377b7ec7b83909b8827e52817c53a47db96cf0', git.head
  end
  
  def test_remote_tracking_setup_reindexes_repo
    git.checkout('track')
    sha = repo.store('content' => 'new doc', 'tags' => ['tag'])
    repo.commit!
    git.checkout('gitgo')
    
    @repo = Gitgo::Repo.new(Gitgo::Repo::GIT => git.clone(method_root.path('clone')))
    
    post("/setup", {:remote_branch => 'origin/track'}, {Gitgo::Repo::REPO => repo})
    assert last_response.redirect?
    assert_equal "/", last_response['Location']
    
    get("/repo/idx/tags/tag", {}, {Gitgo::Repo::REPO => repo})
    assert last_response.ok?
    assert last_response.body.include?(sha), last_response.body
  end
  
  #
  # timeline test
  #
  
  def last_doc
    assert last_response.redirect?
    url, anchor = last_response['Location'].split('#', 2)
    anchor || File.basename(url)
  end
  
  def test_timeline_shows_latest_activity
    post("/issue", "doc[title]" => "New Issue", "doc[state]" => "open", "doc[date]" => "2010-03-19T14:51:53-06:00")
    issue = last_doc
    
    post("/comment", "doc[origin]" => "ee9a1c", "doc[content]" => "New comment", "doc[date]" => "2010-03-19T14:51:54-06:00")
    comment = last_doc
    
    post("/comment", "doc[origin]" => "ee9a1c", "parents" => [comment], "doc[content]" => "Comment on a comment", "doc[date]" => "2010-03-19T14:51:55-06:00")
    assert last_response.redirect?
    
    post("/issue/#{issue}", "doc[origin]" => issue, "parents" => [issue], "doc[state]" => "closed", "doc[date]" => "2010-03-19T14:51:56-06:00")
    assert last_response.redirect? 

    get("/timeline")
    
    assert last_response.body =~ /#{issue}.*ee9a1ca4441ab2bf937808b26eab784f3d041643.*ee9a1ca4441ab2bf937808b26eab784f3d041643.*#{issue}/m
    assert last_response.body =~ /Issue.*Comment.*Comment.*Issue/m, last_response.body
  end
  
  def test_timeline_shows_helpful_message_if_no_results_are_available
    get("/timeline")
    assert last_response.body.include?('No activity yet...'), last_response.body
  end
end