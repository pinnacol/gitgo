require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/documents'

class DocumentTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  def app
    Gitgo::Documents
  end
  
  def setup_app(repo)
    repo = Gitgo::Repo.new(setup_repo(repo))
    app.set :repo, repo
    app.instance_variable_set :@prototype, nil
    repo
  end
  
  #
  # get test
  #

  def test_get_doc_shows_document_and_comments
    setup_app("gitgo.git")

    get("/doc/c1a80236d015d612d6251fca9611847362698e1c")
    assert last_response.ok?
    assert last_response.body.include?('c1a80236d015d612d6251fca9611847362698e1c')
    assert last_response.body.include?('user.two@email.com')
    assert last_response.body.include?('Issue Two Comment')
    assert last_response.body.include?('0407a96aebf2108e60927545f054a02f20e981ac')
    assert last_response.body.include?('user.one@email.com')
    assert last_response.body.include?('closed')
  end

  #
  # post test
  #

  def test_post_creates_document
    repo = setup_app("gitgo.git")

    post("/doc", "content" => "new doc content", "parents[]" => "c1a80236d015d612d6251fca9611847362698e1c", "commit" => "true")
    assert last_response.redirect?, last_response.body
    assert_equal "added 1 document", repo.current.message
  end

end