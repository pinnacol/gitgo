require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/controllers/issue'

class IssueControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :app
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root.path, :is_bare => true)
    @app = Gitgo::Controllers::Issue.new(nil, repo)
  end
  
  # open an issue using a post, and return the sha of the new issue
  def open_issue(title, attrs={})
    attrs["doc[title]"] = title
    attrs["doc[state]"] = 'open'
    post("/issue", attrs)
    last_issue
  end
  
  # close an issue by put
  def update_issue(sha, attrs={})
    issue = repo.scope { Gitgo::Documents::Issue.read(sha) }
    attrs['doc[tags]'] ||= issue.tags
    attrs['doc[origin]'] ||= issue.graph_head
    attrs['doc[parents]'] ||= [sha]
    attrs['doc[state]'] ||= 'closed'
    
    put("/issue/#{sha}", attrs)
  end
  
  def last_issue
    assert last_response.redirect?
    url, anchor = last_response['Location'].split('#', 2)
    anchor || File.basename(url)
  end
  
  #
  # get test
  #
  
  def test_index_filters_tickets_by_tail_state
    a = open_issue("Issue A")
    b = open_issue("Issue B")
    c = open_issue("Issue C")
    update_issue(c)
    
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
  
  def test_index_filters_on_tail_tags
    a = open_issue("Issue A", "doc[tags]" => "one")
    b = open_issue("Issue B", "doc[tags]" => "one")
    update_issue(b, "doc[tags]" => ["two", "three"])
    c = open_issue("Issue C", "doc[tags]" => "two")
    
    get("/issue")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body =~ /Issue C/
    
    get("/issue", "tags" => "one")
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body !~ /Issue B/
    assert last_response.body !~ /Issue C/
    
    get("/issue", "tags" => "two")
    assert last_response.ok?
    
    assert last_response.body !~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body =~ /Issue C/
    
    get("/issue", "tags" => ["two", "three"])
    assert last_response.ok?
    
    assert last_response.body !~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body !~ /Issue C/
  end
  
  def test_index_sorts_by_sort_attribute
    a = open_issue("Issue A")
    b = open_issue("Issue B")
    c = open_issue("Issue C")
    update_issue(c)
    
    get("/issue", "sort" => "title")
    assert last_response.ok?
    assert last_response.body =~ /Issue A.*Issue B.*Issue C/m
    
    get("/issue", "sort" => "title", "reverse" => true)
    assert last_response.ok?
    assert last_response.body =~ /Issue C.*Issue B.*Issue A/m
  end
  
  def test_index_indicates_active_according_to_tails
    repo.git.checkout('master')
    repo['state'] = 'point a -- issue A is open'
    point_a = repo.commit!
    
    repo['state'] = 'point b -- issue B is shown invalid'
    point_b = repo.commit!
    
    repo['state'] = 'point c -- issue C is open, B is open'
    point_c = repo.commit!
    
    repo.git.checkout('gitgo')
    a = open_issue("Issue A", "doc[at]" => point_a)
    b = open_issue("Issue B", "doc[at]" => point_c)
    c = open_issue("Issue C", "doc[at]" => point_c)
    update_issue(c, "doc[at]" => point_b)
    
    head = Gitgo::Controller::HEAD
    get("/issue", {}, {'rack.session' => {head => point_c}})
    assert last_response.ok?
    assert last_response.body =~ /id="#{a}" active="true"/
    assert last_response.body =~ /id="#{b}" active="true"/
    assert last_response.body =~ /id="#{c}" active="true"/
    
    get("/issue", {}, {'rack.session' => {head => point_b}})
    assert last_response.ok?
    assert last_response.body =~ /id="#{a}" active="true"/
    assert last_response.body =~ /id="#{b}" active="false"/
    assert last_response.body =~ /id="#{c}" active="true"/
    
    get("/issue", {}, {'rack.session' => {head => point_a}})
    assert last_response.ok?
    assert last_response.body =~ /id="#{a}" active="true"/
    assert last_response.body =~ /id="#{b}" active="false"/
    assert last_response.body =~ /id="#{c}" active="false"/
  end
  
  #
  # get /issue/new
  #
  
  def test_get_new_issue_provides_form_for_new_issue
    get("/issue/new")
    assert last_response.ok?
    assert last_response.body =~ /<form .* action="\/issue"/
  end
  
  def test_get_new_issue_previews_content
    get("/issue/new", "preview" => true, "doc[content]" => "h1. A big header")
    assert last_response.ok?
    assert last_response.body.include?("Preview")
    assert last_response.body.include?("<h1>A big header</h1>")
  end
  
  #
  # get /issue/id
  #
  
  def test_get_issue_provides_form_to_close_all_tails
    issue = open_issue("Issue A")
    update_issue(issue, "doc[state]" => "closed")
    a = last_issue
    
    update_issue(issue, "doc[state]" => "invalid")
    b = last_issue
    
    get("/issue/#{issue}")
    assert last_response.ok?
    assert last_response.body.include?(%Q{name="doc[parents][]" value="#{a}"}), last_response.body
    assert last_response.body.include?(%Q{name="doc[parents][]" value="#{b}"})
  end
  
  def test_get_rev_parses_issue
    issue = open_issue("Issue A")
    
    get("/issue/#{issue}")
    assert last_response.ok?
    assert last_response.body.include?("Issue A")
  end
  
  #
  # post test
  #
  
  def test_post_creates_a_new_doc
    post("/issue", "doc[title]" => "New Issue", "doc[state]" => "open")
    issue = repo.read(last_issue)
    
    assert_equal "New Issue", issue['title']
    assert_equal "/issue/#{last_issue}", last_response['Location']
  end
  
  def test_post_rev_parses_at
    @repo = Gitgo::Repo.init(setup_repo("simple.git"))
    @app = Gitgo::Controllers::Issue.new(nil, repo)
    
    #
    post("/issue", "doc[title]" => "title", "doc[state]" => "open", "doc[at]" => 'caps')
    assert last_response.redirect?
    
    issue = repo.read(last_issue)
    assert_equal "19377b7ec7b83909b8827e52817c53a47db96cf0", issue['at']
  end
  
  def test_post_links_issue_to_parents
    post("/issue", "doc[title]" => "a", "doc[state]" => "open")
    parent = last_issue
    
    post("/issue", "doc[title]" => "b", "doc[state]" => "open", "doc[origin]" => parent, "doc[parents]" => [parent])
    
    child = last_issue
    assert_equal [child], repo.links(parent)
  end
  
  def test_post_rev_parses_parents
    post("/issue", "doc[title]" => "a", "doc[state]" => "open")
    parent = last_issue
    
    post("/issue", "doc[title]" => "b", "doc[state]" => "open", "doc[origin]" => parent, "doc[parents]" => [parent[0,8]])
    
    child = last_issue
    assert_equal [child], repo.graph(parent).children
  end
  
  def test_put_raises_error_for_invalid_parents
    post("/issue", "doc[title]" => "a", "doc[state]" => "open")
    parent = last_issue
    
    err = assert_raises(RuntimeError) do
      post("/issue", "doc[title]" => "b", "doc[state]" => "open", "doc[parents]" => [parent])
    end
    
    assert_equal 'parent and child have different origins', err.message
  end
  
  def test_post_with_preview_renders_preview
    post("/issue", "doc[content]" => "h1. Description", "doc[state]" => "open", "preview" => "true")
    assert last_response.ok?
    assert last_response.body.include?("Preview")
    assert last_response.body.include?("<h1>Description</h1>")
  end
  
  def test_post_to_sha_with_preview_renders_show_and_preview
    post("/issue", "doc[title]" => "parent title", "doc[state]" => "open")
    parent = last_issue
    
    post("/issue/#{parent}", "doc[title]" => "child title", "doc[content]" => "h1. Update", "doc[state]" => "open", "preview" => "true")
    assert last_response.ok?
    assert last_response.body.include?("parent title")
    assert last_response.body.include?("Preview")
    assert last_response.body.include?("<h1>Update</h1>")
  end
  
  def test_post_raises_error_if_no_meaningful_title_is_given
    err = assert_raises(Gitgo::Document::InvalidDocumentError) { post("/issue", "doc[title]" => "  \n \t\t \r ", "doc[state]" => "open") }
    assert_equal "nothing specified", err.errors['title'].message
  end
end