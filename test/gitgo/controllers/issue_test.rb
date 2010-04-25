require File.dirname(__FILE__) + '/../../test_helper'
require 'gitgo/controllers/issue'

class IssueControllerTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  Issue = Gitgo::Documents::Issue
  
  attr_reader :app
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root.path, :is_bare => true)
    @app = Gitgo::Controllers::Issue.new(nil, repo)
  end
  
  def save(attrs)
    repo.scope { Issue.save(attrs) }
  end
  
  def create(attrs)
    repo.scope { Issue.create(attrs) }
  end
  
  def update(doc, attrs)
    repo.scope { Issue.update(doc, attrs) }
  end
  
  def last_issue
    assert last_response.redirect?
    url, anchor = last_response['Location'].split('#', 2)
    anchor || File.basename(url)
  end
  
  #
  # get test
  #
  
  def test_index_filters_issues_by_graph_tails
    a = create('title' => 'Issue A', 'tags' => ['open'])
    b = create('title' => 'Issue B', 'tags' => ['open'])
    c = create('title' => 'Issue C', 'tags' => ['open'])
    update(c, 'tags' => ['closed'])
    
    get('/issue')
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body =~ /Issue C/
    
    get('/issue?tags[]=open')
    assert last_response.ok?
    
    assert last_response.body =~ /Issue A/
    assert last_response.body =~ /Issue B/
    assert last_response.body !~ /Issue C/
    
    get('/issue?tags[]=closed')
    assert last_response.ok?
    
    assert last_response.body !~ /Issue A/
    assert last_response.body !~ /Issue B/
    assert last_response.body =~ /Issue C/
  end
  
  def test_index_sorts_by_sort_attribute
    a = create('title' => 'Issue A')
    b = create('title' => 'Issue B')
    c = create('title' => 'Issue C')
    
    get('/issue', 'sort' => 'title')
    assert last_response.ok?
    assert last_response.body =~ /Issue A.*Issue B.*Issue C/m
    
    get('/issue', 'sort' => 'title', 'reverse' => true)
    assert last_response.ok?
    assert last_response.body =~ /Issue C.*Issue B.*Issue A/m
  end
  
  def test_index_indicates_active_according_to_graph_tails
    repo.git.checkout('master')
    repo['file'] = 'a'
    commit_a = repo.commit!
    
    repo['file'] = 'b'
    commit_b = repo.commit!
    
    repo['file'] = 'c'
    commit_c = repo.commit!
    
    repo.git.checkout('gitgo')
    a = create('title' => 'Issue A', 'at' => commit_a).sha
    b = create('title' => 'Issue B', 'at' => commit_c).sha
    c = create('title' => 'Issue C', 'at' => commit_c).sha
    update(c, 'at' => commit_b)
    
    head = Gitgo::Controller::HEAD
    get('/issue', {}, {'rack.session' => {head => commit_c}})
    assert last_response.ok?
    assert last_response.body =~ /id="#{a}" active="true"/
    assert last_response.body =~ /id="#{b}" active="true"/
    assert last_response.body =~ /id="#{c}" active="true"/
    
    get('/issue', {}, {'rack.session' => {head => commit_b}})
    assert last_response.ok?
    assert last_response.body =~ /id="#{a}" active="true"/
    assert last_response.body =~ /id="#{b}" active="false"/
    assert last_response.body =~ /id="#{c}" active="true"/
    
    get('/issue', {}, {'rack.session' => {head => commit_a}})
    assert last_response.ok?
    assert last_response.body =~ /id="#{a}" active="true"/
    assert last_response.body =~ /id="#{b}" active="false"/
    assert last_response.body =~ /id="#{c}" active="false"/
  end
  
  #
  # get /issue/new
  #
  
  def test_get_new_issue_provides_form_for_new_issue
    get('/issue/new')
    assert last_response.ok?
    assert last_response.body =~ /<form .* action="\/issue"/
  end
  
  def test_get_new_issue_previews_content
    get('/issue/new', 'preview' => true, 'doc[content]' => 'h1. A big header')
    assert last_response.ok?
    assert last_response.body.include?('Preview')
    assert last_response.body.include?('<h1>A big header</h1>')
  end
  
  #
  # get /issue/id
  #
  
  def test_get_issue_provides_form_to_link_to_all_tails
    a = create('title' => 'Issue A')
    b = save('title' => 'Issue B').link_to(a)
    c = save('title' => 'Issue C').link_to(a)
    
    get("/issue/#{a.sha}")
    assert last_response.ok?
    assert last_response.body.include?(%Q{name="parents[]" value="#{b.sha}"})
    assert last_response.body.include?(%Q{name="parents[]" value="#{c.sha}"})
  end
  
  def test_get_rev_parses_issue
    a = create('title' => 'Issue A')
    
    get("/issue/#{a.sha[0,8]}")
    assert last_response.ok?
    assert last_response.body.include?('Issue A')
  end
  
  #
  # post test
  #
  
  def test_post_creates_a_new_doc
    post('/issue', 'doc[title]' => 'New Issue')
    issue = repo.read(last_issue)
    
    assert_equal 'New Issue', issue['title']
    assert_equal "/issue/#{last_issue}", last_response['Location']
  end
  
  def test_post_links_issue_to_parents
    a = create('title' => 'a')
    b = update(a, 'title' => 'b')
    c = update(a, 'title' => 'c')
    post('/issue', 'doc[title]' => 'd', 'parents' => [b.sha, c.sha[0,8]])
    
    d = last_issue
    graph = repo.scope { Issue[d].graph }
    assert_equal [d], graph[b.sha].children
    assert_equal [d], graph[c.sha].children
  end
  
  def test_post_raises_error_for_invalid_parent
    err = assert_raises(RuntimeError) { post('/issue', 'doc[title]' => 'a', 'parents' => ['invalid']) }
    assert_equal "invalid parent: \"invalid\"", err.message
    
    a = create('title' => 'a')
    b = create('title' => 'b')
    err = assert_raises(RuntimeError) { post('/issue', 'doc[title]' => 'c', 'parents' => [a.sha, b.sha]) }
    assert_equal "cannot link to unrelated documents: #{[a.sha, b.sha].inspect}", err.message
  end
  
  def test_post_with_preview_renders_preview
    post('/issue', 'doc[content]' => 'h1. Description', 'preview' => 'true')
    assert last_response.ok?
    assert last_response.body.include?('Preview')
    assert last_response.body.include?('<h1>Description</h1>')
  end
  
  def test_post_to_issue_with_preview_renders_show_and_preview
    parent = create('title' => 'Parent').sha
    post("/issue/#{parent}", 'doc[title]' => 'Child', 'doc[content]' => 'h1. Update', 'preview' => 'true')
    
    assert last_response.ok?
    assert last_response.body.include?('Parent')
    assert last_response.body.include?('Preview')
    assert last_response.body.include?('<h1>Update</h1>')
  end
end