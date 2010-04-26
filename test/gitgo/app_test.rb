require File.dirname(__FILE__) + '/../test_helper'
require 'gitgo/app'

class AppTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :app
  attr_reader :repo
  attr_reader :server
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root.path)
    @server = Gitgo::App.new
    
    @app = lambda do |env|
      env[Gitgo::Repo::REPO] = repo
      server.call(env)
    end
  end
  
  #
  # welcome test
  #
  
  def test_welcome_provides_form_to_track_gitgo_branches
    repo.git.checkout('one')
    repo.setup!
    
    repo.git.checkout('two')
    repo.setup!
    
    repo.git.checkout('master')
    get('/welcome')
    
    assert last_response.body.include?('<option value="one"')
    assert last_response.body.include?('<option value="one"')
    assert last_response.body.include?('<input type="submit"')
  end
  
  def test_welcome_skips_the_form_if_no_gitgo_branches_are_available
    get('/welcome')
    assert !last_response.body.include?('<input type="submit"')
  end
  
  #
  # timeline test
  #
  
  def last_doc
    assert last_response.redirect?
    url, anchor = File.basename(last_response['Location']).split('#', 2)
    anchor || url
  end
  
  def test_timeline_shows_latest_activity
    sha = repo.empty_sha
    
    post('/issue', 'doc[title]' => 'New Issue', 'doc[tags]' => 'open', 'doc[date]' => '2010-03-19T14:51:53-06:00')
    a = last_doc
    
    post('/comment', 'doc[content]' => 'New comment', 'doc[re]' => sha, 'doc[date]' => '2010-03-19T14:51:54-06:00')
    b = last_doc
    
    post('/comment', 'doc[content]' => 'Comment on a comment', 'doc[re]' => sha, 'parents' => [b], 'doc[date]' => '2010-03-19T14:51:55-06:00')
    c = last_doc
    
    post("/issue", 'parents' => [a], 'doc[tags]' => 'closed', 'doc[date]' => '2010-03-19T14:51:56-06:00')
    d = last_doc

    get('/timeline')
    
    assert last_response.body =~ /#{a}##{d}.*#{b}##{c}.*#{b}.*#{a}/m
    assert last_response.body =~ /Issue.*Comment.*Comment.*Issue/m
  end
  
  def test_timeline_shows_helpful_message_if_no_results_are_available
    repo.setup!
    
    get('/timeline')
    assert last_response.body.include?('No activity yet...')
  end
end