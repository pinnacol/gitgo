require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/issues'

class IssuesTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root[:tmp], :bare => true)
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Issues
  end
  
  # open an issue using a post, and return the sha of the new issue
  def open_issue(title)
    post("/issue", "doc[title]" => title)
    last_response_location
  end
  
  # close an issue by put
  def close_issue(id)
    put("/issue/#{id}", "doc[state]" => "closed")
  end
  
  def last_response_location
    File.basename(last_response["Location"])
  end
  
  #
  # get test
  #
  
  def test_get_shows_index_of_tickets_by_state
    a = open_issue("Issue A")
    b = open_issue("Issue B")
    c = open_issue("Issue C")
    close_issue(c)
    
    repo.commit "created fixture"
    
    get("/issue")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body =~ /Issue C/
    
    get("/issue?state=open")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body !~ /Issue C/
    
    get("/issue?state=closed")
    assert last_response.ok?
    
    assert last_response.body !~ /Issue A/
    assert last_response.body !~ /Issue B/
    assert last_response.body =~ /Issue C/
  end
  
  #
  # post test
  #
  
  def test_post_creates_a_new_doc
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    id = last_response_location
    issue = repo.read(id)
    
    assert_equal "New Issue", issue['title']
    assert_equal "Issue Description", issue.content
    assert_equal app.author.email, issue.author.email
    assert_equal [id], repo.children(id, :dir => app::INDEX)
    
    assert_equal "/issue/#{id}", last_response['Location']
  end
  
  def test_post_links_issue_at_commit_referencing_issue
    commit = repo.set(:blob, "")
    
    post("/issue", "at" => commit, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    issue = last_response_location
    assert_equal [issue], repo.children(commit)
    assert_equal issue, repo.ref(commit, issue)
  end
  
  #
  # put test
  #
  
  def test_put_creates_a_comment_on_an_issue
    issue = repo.create("New Issue")
    repo.link(issue, issue, :dir => app::INDEX).commit("created fixture")
    assert_equal [issue], repo.children(issue, :dir => app::INDEX)
    
    put("/issue/#{issue}", "content" => "Comment on the Issue", "commit" => "true")
    assert last_response.redirect?, last_response.body
    assert_equal "/issue/#{issue}", last_response['Location']
    
    id = repo.activity(app.author).first
    comment = repo.read(id)
    
    assert_equal "Comment on the Issue", comment.content
    assert_equal app.author.email, comment.author.email
    assert_equal [id], repo.children(issue)
    assert_equal [id], repo.children(issue, :dir => app::INDEX)
  end
  
  def test_put_links_comment_to_re
    issue = repo.create("New Issue")
    a = repo.create("Comment A")
    
    repo.link(issue, a, :dir => app::INDEX).commit("created fixture")
    assert_equal [a], repo.children(issue, :dir => app::INDEX)
    
    put("/issue/#{issue}", "content" => "Comment on A", "re" => a, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    id = repo.activity(app.author).first
    comment = repo.read(id)
    
    assert_equal "Comment on A", comment.content
    assert_equal [], repo.children(issue)
    assert_equal [id], repo.children(a)
    assert_equal [id], repo.children(issue, :dir => app::INDEX)
  end
  
  def test_put_links_comment_to_multiple_re
    issue = repo.create("New Issue")
    a = repo.create("Comment A")
    b = repo.create("Comment B")
    
    repo.link(issue, a, :dir => app::INDEX)
    repo.link(issue, b, :dir => app::INDEX).commit("created fixture")
    assert_equal [a, b].sort, repo.children(issue, :dir => app::INDEX).sort
    
    put("/issue/#{issue}", "content" => "Comment on A and B", "re" => [a, b], "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    id = repo.activity(app.author).first
    comment = repo.read(id)
    
    assert_equal "Comment on A and B", comment.content
    assert_equal [], repo.children(issue)
    assert_equal [id], repo.children(a)
    assert_equal [id], repo.children(b)
    assert_equal [id], repo.children(issue, :dir => app::INDEX)
  end
  
  def test_put_links_comment_at_commit_referencing_issue
    issue = repo.create("New Issue")
    commit = repo.create("")
    
    put("/issue/#{issue}", "at" => commit, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    comment = repo.activity(app.author).first
    assert_equal [comment], repo.children(commit)
    assert_equal issue, repo.ref(commit, comment)
  end
  
  def test_put_raises_error_for_unknown_issue
    put("/issue/unknown", "content" => "Comment on the Issue", "commit" => "true")
    assert_equal 500, last_response.status
    
    assert last_response.body =~ /unknown issue: "unknown"/
  end
end