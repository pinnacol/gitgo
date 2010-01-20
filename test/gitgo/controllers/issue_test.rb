require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/issue'

class IssueTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root[:tmp], :is_bare => true)
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Controllers::Issue
  end
  
  # open an issue using a post, and return the sha of the new issue
  def open_issue(title, attrs={})
    attrs["doc[title]"] = title
    post("/issue", attrs)
    last_response_location
  end
  
  # close an issue by put
  def close_issue(id)
    put("/issue/#{id}", "doc[state]" => "closed")
  end
  
  def last_response_location
    last_response["Location"] =~ /\/(.{40})(?:\/(.{40}))?\z/
    $2 ? [$1, $2] : $1
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
    assert last_response.ok?, last_response.body
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body !~ /Issue C/
    
    get("/issue?state=closed")
    assert last_response.ok?
    
    assert last_response.body !~ /Issue A/
    assert last_response.body !~ /Issue B/
    assert last_response.body =~ /Issue C/
  end
  
  def test_index_filters_on_all_filter_params
    a = open_issue("Issue A", "doc[tags]" => "one")
    b = open_issue("Issue B", "doc[tags]" => "two")
    close_issue(b)
    c = open_issue("Issue C", "doc[tags]" => "two")
    
    repo.commit "created fixture"
    
    get("/issue")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body =~ /Issue C/
    
    get("/issue", "state" => "open")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body !~ /Issue B/
    assert last_response.body =~ /Issue C/
    
    get("/issue", "state" => "open", "tags" => "one")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body !~ /Issue B/
    assert last_response.body !~ /Issue C/
    
    get("/issue", "state" => ["open", "closed"], "tags" => "two")
    assert last_response.ok?
    
    assert last_response.body !~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body =~ /Issue C/
  end
  
  def test_index_sorts_by_sort_attribute
    a = open_issue("Issue A")
    b = open_issue("Issue B")
    c = open_issue("Issue C")
    close_issue(c)
    
    repo.commit "created fixture"
    
    get("/issue", "sort" => "title")
    assert last_response.ok?
    assert last_response.body =~ /Issue A.*Issue B.*Issue C/m
    
    get("/issue", "sort" => "title", "reverse" => true)
    assert last_response.ok?
    assert last_response.body =~ /Issue C.*Issue B.*Issue A/m
  end
  
  def test_get_new_issue_provides_form_for_new_issue
    get("/issue/new")
    assert last_response.ok?
    assert last_response.body =~ /<form .* action="\/issue"/
  end
  
  #
  # post test
  #
  
  def test_post_creates_a_new_doc
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    assert last_response.redirect?
    
    id = last_response_location
    issue = repo.read(id)
    
    assert_equal "New Issue", issue['title']
    assert_equal "Issue Description", issue.content
    assert_equal app.author.email, issue.author.email
     
    assert_equal "/issue/#{id}", last_response['Location']
  end
  
  def test_post_links_issue_at_commit_referencing_issue
    commit = repo.set(:blob, "")
    
    post("/issue", "doc[at]" => commit, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    issue = last_response_location
    assert_equal [issue], repo.children(commit)
    assert_equal issue, repo.reference(commit, issue)
  end
  
  #
  # put test
  #
  
  def test_put_creates_a_comment_on_an_issue
    issue = open_issue("Issue A")
    assert_equal [], repo.children(issue)
    
    put("/issue/#{issue}", "content" => "Comment on the Issue", "commit" => "true")
    assert last_response.redirect?
    id, comment = last_response_location
    
    assert_equal issue, id
    assert_equal [comment], repo.children(issue)
    
    comment = repo.read(comment)
    assert_equal "Comment on the Issue", comment.content
    assert_equal app.author.email, comment.author.email
  end
  
  def test_put_can_close_an_issue
    issue = open_issue("Issue A")
    repo.commit "created fixture"
    
    get("/issue")
    assert last_response.body =~ /Issue A/
    
    put("/issue/#{issue}", "doc[state]" => "closed", "commit" => "true")
    assert last_response.redirect?
    
    get("/issue", "state" => "open")
    assert last_response.body !~ /Issue A/
    
    get("/issue", "state" => "closed")
    assert last_response.body =~ /Issue A/
  end
  
  def test_put_links_comment_to_re
    issue = open_issue("Issue A")
    a = repo.create("Comment A")
    
    assert_equal [], repo.children(issue)
    assert_equal [], repo.children(a)
    
    put("/issue/#{issue}", "content" => "Comment on A", "re" => a, "commit" => "true")
    assert last_response.redirect?, last_response.body
    id, comment = last_response_location
    
    assert_equal issue, id
    assert_equal [], repo.children(issue)
    assert_equal [comment], repo.children(a)
    
    comment = repo.read(comment)
    assert_equal "Comment on A", comment.content
  end
  
  def test_put_links_comment_to_multiple_re
    issue = repo.create("New Issue")
    a = repo.create("Comment A")
    b = repo.create("Comment B")
    
    assert_equal [], repo.children(issue)
    assert_equal [], repo.children(a)
    assert_equal [], repo.children(a)
    
    put("/issue/#{issue}", "content" => "Comment on A and B", "re" => [a, b], "commit" => "true")
    assert last_response.redirect?, last_response.body
    id, comment = last_response_location
    
    assert_equal issue, id
    assert_equal [], repo.children(issue)
    assert_equal [comment], repo.children(a)
    assert_equal [comment], repo.children(b)
    
    comment = repo.read(comment)
    assert_equal "Comment on A and B", comment.content
  end
  
  def test_put_links_comment_at_commit_referencing_issue
    issue = repo.create("New Issue")
    commit = repo.create("")
    
    put("/issue/#{issue}", "doc[at]" => commit, "commit" => "true")
    assert last_response.redirect?, last_response.body
    id, comment = last_response_location
    
    assert_equal issue, id
    assert_equal [comment], repo.children(commit)
    assert_equal issue, repo.reference(commit, comment)
  end
  
  def test_put_raises_error_for_unknown_issue
    put("/issue/unknown", "content" => "Comment on the Issue", "commit" => "true")
    assert_equal 500, last_response.status
    
    assert last_response.body =~ /unknown issue: &quot;unknown&quot;/
  end
end