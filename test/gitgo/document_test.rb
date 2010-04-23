require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/document'

class DocumentTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  Document = Gitgo::Document
  InvalidDocumentError = Document::InvalidDocumentError
  
  attr_accessor :author, :doc
  
  def setup
    super
    
    @author = Grit::Actor.new("John Doe", "john.doe@email.com")
    @current = Repo.set_env(Repo::PATH => method_root.path(:repo), Repo::OPTIONS => {:author => author})
    @doc = Document.new
  end
  
  def teardown
    Repo.set_env(@current)
    super
  end
  
  def repo
    Repo.current
  end
  
  def git
    repo.git
  end
  
  def index
    repo.index
  end
  
  def deserialize(str)
    JSON.parse(str)
  end
  
  #
  # Document.validators test
  #

  class ValidatorA < Document
    validate(:a, :validator)
    validate(:b)
    
    def validator(value)
      raise("got: #{value}")
    end
  end
  
  def test_validate_binds_validator_to_method_name
    assert_equal :validator, ValidatorA.validators['a']
  end
  
  def test_validate_infers_default_validator_name
    assert_equal :validate_b, ValidatorA.validators['b']
  end
  
  def test_validator_is_called_with_attrs_value_to_determine_errors
    a = ValidatorA.new 'a' => 'value'
    assert_equal 'got: value', a.errors['a'].message
  end
  
  class ValidatorB < ValidatorA
    validate(:c, :validator)
  end
  
  def test_validators_are_inherited_down_but_not_up
    a = ValidatorA.new 'a' => 'A', 'c' => 'C'
    assert_equal 'got: A', a.errors['a'].message
    assert_equal nil, a.errors['c']
    
    b = ValidatorB.new 'a' => 'A', 'c' => 'C'
    assert_equal 'got: A', b.errors['a'].message
    assert_equal 'got: C', b.errors['c'].message
  end
  
  #
  # Document.define_attributes test
  #
  
  class DefineAttributesA < Document
    define_attributes do
      attr_reader :reader
      attr_writer :writer
      attr_accessor :accessor
    end
  end
  
  def test_define_attributes_causes_attr_x_methods_to_read_and_write_attrs
    a = DefineAttributesA.new

    assert_equal true, a.respond_to?(:reader)
    assert_equal false, a.respond_to?(:reader=)
    assert_equal false, a.respond_to?(:writer)
    assert_equal true, a.respond_to?(:writer=)
    assert_equal true, a.respond_to?(:accessor)
    assert_equal true, a.respond_to?(:accessor=)
    
    a.attrs['reader'] = 'one'
    assert_equal 'one', a.reader
    
    a.writer = 'two'
    assert_equal 'two', a.attrs['writer']
    
    a.accessor = 'three'
    assert_equal 'three', a.attrs['accessor']
    
    a.attrs['accessor'] = 'four'
    assert_equal 'four', a.accessor
  end
  
  class DefineAttributesB < Document
    define_attributes do
      attr_reader :not_validated
      attr_writer(:validated) {|value| raise('msg') if value.nil? }
      attr_accessor(:also_validated) {|value| raise('msg') if value.nil? }
    end
  end
  
  def test_define_attributes_causes_attr_writer_to_create_validator_from_block
    assert_equal nil, DefineAttributesB.validators['not_validated']
    assert_equal :validate_validated, DefineAttributesB.validators['validated']
    assert_equal :validate_also_validated, DefineAttributesB.validators['also_validated']
  end
  
  #
  # Document.register_as test
  #
  
  class RegisterClass < Document
    register_as 'type'
  end
  
  def test_register_as_registers_class_to_type
    assert_equal RegisterClass, Document.types['type']
  end
  
  def test_types_are_shared_among_all_documents
    assert_equal Document.types.object_id, RegisterClass.types.object_id
  end
  
  class AutoRegisterClass < Document
  end
  
  def test_subclasses_are_automatically_registered_by_downcased_const_name
    assert_equal AutoRegisterClass, Document.types['autoregisterclass']
  end
  
  #
  # Document.save test
  #
  
  def test_save_initializes_doc_and_saves
    a = Document.save('content' => 'a')
    assert_equal true, a.saved?
    
    attrs = deserialize(git.get(:blob, a.sha).data)
    assert_equal 'a', attrs['content']
  end
  
  def test_save_documents_have_no_associations
    a = Document.save('content' => 'a')
    assert_equal({}, repo.associations(a.sha))
  end
  
  def test_saved_documents_can_be_linked_and_updated
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    c = Document.save('content' => 'c')
    d = Document.save('content' => 'd')
    
    a.link(b)
    a.link(c)
    c.update(d)
    
    assert_equal [a.sha], d.node.parents
    assert_equal [b.sha, d.sha].sort, a.node.children.sort
  end
  
  def test_save_caches_document_attrs
    assert_equal({}, repo.cache)
    
    a = Document.save('content' => 'a')
    assert_equal({a.sha => a.attrs}, repo.cache)
  end
  
  def test_save_indexes_document
    a = Document.save('tags' => 'tag')
    assert_equal [a.idx], index['tags']['tag']
  end
  
  #
  # Document.create test
  #
  
  def test_create_saves_doc_and_stores_using_a_create_association
    a = Document.create('content' => 'a')
    assert_equal true, a.saved?
    
    attrs = deserialize(git.get(:blob, a.sha).data)
    assert_equal 'a', attrs['content']
    
    assert_equal({:create => true}, repo.associations(a.sha))
  end
  
  def test_create_indexes_document
    a = Document.create('tags' => 'tag')
    assert_equal [a.idx], index['tags']['tag']
  end
  
  #
  # Document.read test
  #
  
  def test_read_reads_document
    doc['content'] = 'a'
    doc.save
    
    assert_equal 'a', Document.read(doc.sha)['content']
  end
  
  class ReadClass < Document
    register_as 'read_type'
  end
  
  def test_read_casts_document_to_registered_type
    doc.type = 'read_type'
    doc.save
    
    result = Document.read(doc.sha)
    assert_equal ReadClass, result.class
  end
  
  #
  # Document.update test
  #
  
  def test_update_documentation
    a = Document.create('content' => 'a')
    b = Document.update(a, 'content' => 'b')
    c = Document.update(a, 'content' => 'c')
  
    d = Document.update(b, 'content' => 'd')
    c.update(d)
  
    a.reset
    assert_equal [d.sha], a.node.versions.uniq
  end
  
  def test_update_merges_attrs_with_old_doc_and_returns_new_doc
    a = Document.create('content' => 'a', 'tags' => 'one')
    b = Document.update(a, 'content' => 'b')
    
    assert_equal 'a', a['content']
    assert_equal 'b', b['content']
    assert_equal ['one'], b['tags']
    
    assert_equal({:create => true, :updates => [b.sha]}, repo.associations(a.sha))
    assert_equal({}, repo.associations(b.sha))
  end
  
  def test_update_indexes_document
    a = Document.create
    b = Document.update(a, 'tags' => 'tag')
    assert_equal [b.idx], index['tags']['tag']
  end
  
  #
  # Document.find test
  #
  
  def test_find_returns_documents_matching_criteria
    a = Document.create('content' => 'a', 'tags' => ['one'])
    b = Document.create('content' => 'b', 'tags' => ['one', 'two'])
    c = Document.create('content' => 'c', 'tags' => ['two'])
    
    results = Document.find
    assert_equal [a, b, c], results
    
    results = Document.find('tags' => 'one')
    assert_equal [a, b], results
    
    results = Document.find('tags' => 'three')
    assert_equal [], results
    
    results = Document.find('tags' => ['one', 'two'])
    assert_equal [b], results
    
    results = Document.find(nil, {'tags' => ['one', 'two']})
    assert_equal [a, b, c], results
    
    results = Document.find({'tags' => 'one'}, {'tags' => ['two']})
    assert_equal [b], results
  end
  
  def test_find_caches_documents
    a = Document.create('content' => 'a', 'tags' => ['one'])
    
    assert_equal [a], Document.find
    assert_equal({a.sha => a.attrs}, repo.cache)
  end
  
  class FindDoc < Document
  end
  
  def test_find_filters_by_type_if_specified
    a = Document.create('content' => 'a')
    b = FindDoc.create('content' => 'b')
    c = FindDoc.create('content' => 'c')
    
    assert_equal [a, b, c], Document.find
    assert_equal [b, c], FindDoc.find
  end
  
  #
  # update_index test
  #
  
  def test_update_index_indexes_docs_from_index_head_to_repo_head
    a = Document.create('content' => 'a', 'tags' => ['one']).sha
    one = repo.commit
    
    b = Document.create('content' => 'c', 'tags' => ['one']).sha
    two = repo.commit
    
    c = Document.create('content' => 'b', 'tags' => ['one']).sha
    three = repo.commit
    
    index.clear
    Document.update_index
    assert_equal [a, b, c].sort, index.select(:all => {'tags' => 'one'}, :shas => true).sort
    
    index.clear
    index.write(one)
    Document.update_index
    assert_equal [b, c].sort, index.select(:all => {'tags' => 'one'}, :shas => true).sort
    
    index.clear
    index.write(one)
    git.checkout(two)
    Document.update_index
    assert_equal [b].sort, index.select(:all => {'tags' => 'one'}, :shas => true).sort
  end
  
  def test_update_index_updates_index_head_to_repo_head
    Document.create
    index.clear
    
    assert_equal nil, index.head
    Document.update_index
    assert_equal repo.head, index.head
  end
  
  def test_update_index_does_not_update_index_head_if_repo_head_is_nil
    assert_equal nil, index.head
    Document.update_index
    assert_equal nil, index.head
  end
  
  def test_update_index_clears_existing_index_if_specified
    index['key']['value'] = [1]
    
    assert_equal [1], index['key']['value']
    Document.update_index(true)
    assert_equal [], index['key']['value']
  end
  
  def test_update_caches_doc_attrs
    assert_equal({}, repo.cache)
  
    a = Document.create('content' => 'a')
    b = Document.update(a.sha, 'content' => 'b')
    assert_equal({a.sha => a.attrs, b.sha => b.attrs}, repo.cache)
  end
  
  #
  # Document[] test
  #
  
  def test_Document_AGET_reads_attrs_from_cache_and_casts_to_document
    a = Document.create('content' => 'a')
    b = Document[a.sha]
    
    assert_equal 'a', b['content']
    assert_equal({a.sha => b.attrs}, repo.cache)
  end
  
  #
  # initialize test
  #
  
  def test_initialize_does_not_parse_attributes
    doc = Document.new('author' => 'Jane Doe <jane.doe@email.com>')
    assert_equal({'author' => 'Jane Doe <jane.doe@email.com>'}, doc.attrs)
  end
  
  def test_initialize_uses_current_repo_unless_specified
    doc = Document.new
    assert_equal Repo.current, doc.repo
  end
  
  #
  # idx test
  #
  
  def test_idx_returns_nil_for_unsaved_document
    assert_equal nil, doc.idx
  end
  
  def test_idx_returns_idx_of_document_in_index_list
    doc.save
    assert_equal 0, doc.idx
    assert_equal [doc.sha], index.list
    
    index.list.clear
    index.list.concat ['notsha', doc.sha, 'notsha']
    assert_equal 1, doc.idx
  end
  
  #
  # graph_head test
  #
  
  def test_graph_head_returns_nil_for_unsaved_document
    assert_equal nil, doc.graph_head
  end
  
  def test_graph_head_returns_the_sha_for_the_graph_head_doc_belongs_to
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    c = Document.save('content' => 'c')
    
    a.link(b)
    a.update(c)
    
    assert_equal a.sha, a.graph_head
    assert_equal a.sha, b.graph_head
    assert_equal a.sha, c.graph_head
  end
  
  #
  # graph_head? test
  #
  
  def test_graph_head_check_returns_true_for_unsaved_document
    assert_equal true, doc.graph_head?
  end
  
  def test_graph_head_check_returns_true_for_graph_heads
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    c = Document.save('content' => 'c')

    a.link(b)
    a.update(c)
    
    assert_equal true, a.graph_head?
    assert_equal false, b.graph_head?
    assert_equal false, c.graph_head?
  end
  
  #
  # graph test
  #
  
  def test_graph_returns_empty_graph_for_unsaved_document
    assert_equal true, doc.graph.empty?
  end
  
  #
  # node test
  #
  
  def test_node_returns_node_for_unsaved_document
    assert_equal nil, doc.node.sha
  end
  
  #
  # author= test
  #
  
  def test_set_author_stringifies_actors
    doc.author = author
    assert_equal 'John Doe <john.doe@email.com>', doc.attrs['author']
  end
  
  #
  # author test
  #
  
  def test_author_casts_string_author_to_actor_if_cast_is_specified
    doc.attrs['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal Grit::Actor, doc.author.class
    assert_equal String, doc.author(false).class
  end
  
  def test_author_does_not_attempt_to_cast_nil_authors
    doc.attrs['author'] = nil
    assert_equal nil, doc.author
    assert_equal nil, doc.author(false)
  end
  
  #
  # date= test
  #
  
  def test_set_date_converts_inputs_using_iso8601_if_possible
    date = Time.now
    doc.date = date
    assert_equal date.iso8601, doc.attrs['date']
  end
  
  #
  # date test
  #
  
  def test_date_casts_string_date_to_Time_if_cast_is_specified
    doc.attrs['date'] = Time.now.iso8601
    assert_equal Time, doc.date.class
    assert_equal String, doc.date(false).class
  end
  
  def test_date_does_not_attempt_to_cast_nil_dates
    doc.attrs['date'] = nil
    assert_equal nil, doc.date
    assert_equal nil, doc.date(false)
  end
  
  #
  # AGET test
  #
  
  def test_AGET_gets_attribute_from_attrs
    doc = Document.new
    doc.attrs['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal 'Jane Doe <jane.doe@email.com>', doc['author']
  end
  
  #
  # ASET test
  #
  
  def test_ASET_sets_attribute_into_attrs
    doc = Document.new
    doc['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal 'Jane Doe <jane.doe@email.com>', doc.attrs['author']
  end
  
  #
  # tail? test
  #
  
  def test_tail_check_returns_false_unless_doc_is_tail
    doc.merge!('content' => 'a').save.create
    assert_equal true, doc.node.tail?
    
    # update
    update = doc.merge('content' => 'b').save
    doc.update(update)
    
    assert_equal true, update.node.tail?
    assert_equal false, doc.node.tail?
    
    # child
    child = Document.save('content' => 'c')
    update.link(child)
    
    assert_equal false, update.node.tail?
  end
  
  #
  # active? test
  #
  
  def test_active_returns_true_if_at_is_in_rev_list_for_commit
    git['one'] = 'A'
    one = git.commit("added one")
    
    git['two'] = 'B'
    two = git.commit("added two")
    
    doc.at = one
    assert_equal true, doc.active?(one)
    assert_equal true, doc.active?(two)
    
    doc.at = two
    assert_equal false, doc.active?(one)
    assert_equal true, doc.active?(two)
  end
  
  def test_active_returns_true_if_commit_is_nil
    assert_equal true, doc.active?(nil)
  end
  
  def test_active_returns_true_if_at_is_not_set
    git['one'] = 'A'
    one = git.commit("added one")
    
    assert_equal true, doc.active?(one)
  end
  
  #
  # parents test
  #
  
  def test_parents_queries_graph_for_parents
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.link(b)
    
    assert_equal [a.sha], b.node.parents
  end
  
  #
  # children test
  #
  
  def test_children_queries_graph_for_children
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.link(b)
    
    assert_equal [b.sha], a.node.children
  end
  
  #
  # merge test
  #
  
  def test_merge_duplicates_and_merge_bangs_attrs
    doc.attrs['one'] = 'one'
    doc.attrs['two'] = 'two'
    dup = doc.merge('two' => 'TWO', 'three' => 'THREE')
    
    assert_equal({'one' => 'one', 'two' => 'two'}, doc.attrs)
    assert_equal({'one' => 'one', 'two' => 'TWO', 'three' => 'THREE'}, dup.attrs)
  end
  
  #
  # merge! test
  #
  
  def test_merge_bang_merges_new_attrs_with_existing
    doc.attrs['one'] = 'one'
    doc.attrs['two'] = 'two'
    doc.merge!('two' => 'TWO', 'three' => 'THREE')
    
    assert_equal({'one' => 'one', 'two' => 'TWO', 'three' => 'THREE'}, doc.attrs)
  end
  
  #
  # errors test
  #
  
  class ErrorDoc < Document
    validate(:must_be_specifed) {|value| raise("not specified") if value.nil? }
  end
  
  def test_errors_detects_missing_attrs
    doc = ErrorDoc.new
    assert_equal nil, doc['must_be_specifed']
    assert_equal 'not specified', doc.errors['must_be_specifed'].message
  end
  
  def test_errors_detects_missing_author
    doc.author = nil
    assert_equal 'missing', doc.errors['author'].message
  end
  
  def test_errors_detects_misformatted_author
    doc.author = 'No Email'
    assert_equal 'misformatted', doc.errors['author'].message
  end
  
  def test_errors_detects_missing_date
    doc.date = nil
    assert_equal 'missing', doc.errors['date'].message
  end
  
  def test_errors_detects_misformatted_date
    doc.date = '12345'
    assert_equal 'misformatted', doc.errors['date'].message
  end
  
  def test_errors_detects_non_sha_at
    doc.at = 'notasha'
    assert_equal 'misformatted', doc.errors['at'].message
  end
  
  def test_errors_detects_non_array_tags
    doc.tags = 'tag'
    assert_equal 'not an array', doc.errors['tags'].message
  end
  
  #
  # normalize test
  #
  
  def test_normalize_returns_duplicate_that_has_been_normalized
    doc['key'] = 'value'
    norm = doc.normalize
    
    assert_equal nil, doc.author
    assert_equal author.email, norm.author.email
    assert_equal 'value', norm['key']
  end
  
  #
  # normalize! test
  #
  
  def test_normalize_bang_sets_author_using_repo_author_if_unset
    assert_equal nil, doc.author
    doc.normalize!
    assert_equal author.email, doc.author.email
  end
  
  def test_normalize_bang_sets_date_if_unset
    assert_equal nil, doc.date
    doc.normalize!
    assert_in_delta Time.now.to_f, doc.date.to_f, 1
  end
  
  def test_normalize_bang_resolves_at_if_set
    a = git['a'] = 'content'
    git.commit('added blob')
    
    doc.at = a[0, 8]
    doc.normalize!
    assert_equal a, doc.at
  end
  
  def test_normalize_bang_arrayifies_tags
    doc.tags = 'tag'
    doc.normalize!
    assert_equal ['tag'], doc.tags
  end
  
  class RegisterDoc < Document
    register_as 'reg_doc'
  end
  
  def test_normalize_bang_sets_type_registered_to_class
    doc = RegisterDoc.new
    doc.normalize!
    assert_equal 'reg_doc', doc.type
  end
  
  def test_normalize_bang_does_not_set_type_if_class_is_not_registered
    assert_equal nil, Document.type
    
    doc.normalize!
    assert_equal nil, doc.type
    assert_equal false, doc.attrs.has_key?('type')
  end
  
  #
  # indexes test
  #
  
  def test_indexes_includes_author_email
    doc['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal [['email', 'jane.doe@email.com']], doc.indexes
  end
  
  def test_indexes_uses_unknown_as_author_email_if_no_email_is_provided
    doc['author'] = 'Jane Doe <>'
    assert_equal [['email', 'unknown']], doc.indexes
    
    doc['author'] = 'Jane Doe < >'
    assert_equal [['email', 'unknown']], doc.indexes
    
    doc['author'] = 'Jane Doe'
    assert_equal [['email', 'unknown']], doc.indexes
  end
  
  def test_indexes_includes_date
    doc['date'] = Time.utc(2008, 8, 9).iso8601
    assert_equal [['date', '20080809']], doc.indexes
  end
  
  def test_indexes_includes_each_tag_individually
    doc['tags'] = ['one', 'two']
    
    assert_equal [
      ['tags', 'one'],
      ['tags', 'two']
    ], doc.indexes
  end
  
  def test_indexes_includes_at
    doc['at'] = 'sha'
    assert_equal [['at', 'sha']], doc.indexes
  end
  
  def test_indexes_includes_type
    doc['type'] = 'doc'
    assert_equal [['type', 'doc']], doc.indexes
  end
  
  #
  # each_index test
  #
  
  def test_each_index_yields_index_pairs_to_block
    doc['author'] = 'Jane Doe <jane.doe@email.com>'
    
    pairs = []
    doc.each_index {|key, value| pairs << [key, value]}
    assert_equal [['email', 'jane.doe@email.com']], pairs
  end
  
  #
  # save test
  #
  
  def test_save_stores_attrs_and_sets_sha
    doc['key'] = 'value'
    doc.save
    
    attrs = repo.read(doc.sha)
    assert_equal 'value', attrs['key']
  end
  
  def test_multiple_sequential_saves_do_not_change_sha
    a = doc.save.sha
    b = doc.save.sha
    
    assert_equal a, b
  end
  
  class SaveDoc < Document
    validate(:key) {|key| raise("no key") if key.nil? }
  end
  
  def test_save_validates_doc
    doc = SaveDoc.new
    err = assert_raises(InvalidDocumentError) { doc.save }
    assert_equal "no key", err.errors['key'].message
    assert_equal nil, doc.sha
    
    doc['key'] = 'value'
    doc.save
    attrs = repo.read(doc.sha)
    assert_equal 'value', attrs['key']
  end
  
  class NormDoc < Document
    validate(:key) {|key| raise("nil key") if key.nil? }
    
    def normalize!
      super
      attrs['key'] = 'value' unless attrs.has_key?('key')
    end
  end
  
  def test_save_normalizes_doc_before_validate
    doc = NormDoc.new
    doc.save
    assert_equal 'value', doc['key']
    
    doc = NormDoc.new 'key' => nil
    err = assert_raises(InvalidDocumentError) { doc.save }
    assert_equal "nil key", err.errors['key'].message
  end
  
  def test_save_does_not_create_associations
    doc.save
    assert_equal({}, repo.associations(doc.sha))
  end
  
  #
  # saved? test
  #
  
  def test_saved_check_returns_true_if_saved
    assert_equal false, doc.saved?
    doc.save
    assert_equal true, doc.saved?
  end
  
  #
  # create test
  #
  
  def test_create_creates_create_association
    doc.save.create
    assert_equal({:create => true}, repo.associations(doc.sha))
  end
  
  def test_create_raises_error_if_unsaved
    err = assert_raises(RuntimeError) { doc.create }
    assert_equal "cannot create unless saved", err.message
  end
  
  def test_create_raises_error_if_doc_already_belongs_to_a_graph
    head = Document.create('content' => 'a')
    head.link doc.save
    
    err = assert_raises(RuntimeError) { doc.create }
    assert_equal "create graph fail: #{doc.sha} (already associated with graph #{head.sha})", err.message
  end
  
  #
  # update test
  #
  
  def test_update_updates_self_to_new_doc
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    
    a.update(b)
    
    attrs = deserialize(git.get(:blob, b.sha).data)
    assert_equal 'b', attrs['content']
    assert_equal [b.sha], a.node.versions
    assert_equal false, a.node.current?
  end
  
  def test_update_creates_update_association
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    
    a.update(b)
    assert_equal({:create => true, :updates => [b.sha]}, repo.associations(a.sha))
  end
  
  def test_update_raises_error_if_unsaved
    new_doc = Document.save('content' => 'new_doc')
    err = assert_raises(RuntimeError) { doc.update(new_doc) }
    assert_equal "cannot update unless saved", err.message
  end
  
  def test_update_raises_error_if_new_doc_is_unsaved
    new_doc = Document.new('content' => 'new_doc')
    doc.save
    
    err = assert_raises(RuntimeError) { doc.update(new_doc) }
    assert_equal "cannot update with an unsaved document: #{new_doc.inspect}", err.message
  end
  
  def test_update_raises_error_if_document_does_not_belong_to_a_graph
    a = Document.save('content' => 'a')
    b = Document.save('content' => 'b')
    
    err = assert_raises(RuntimeError) { a.update(b) }
    assert_equal "update fail: #{a.sha} -> #{b.sha} (source is not associated with a graph)", err.message
  end
  
  def test_update_raises_error_if_new_doc_belongs_to_a_different_graph
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.update(b)
    
    c = Document.create('content' => 'c')
    d = Document.save('content' => 'd')
    c.update(d)
    
    err = assert_raises(RuntimeError) { b.update(d) }
    assert_equal "update fail: #{b.sha} -> #{d.sha} (different graph heads #{a.sha}/#{c.sha})", err.message
  end
  
  def test_update_raises_error_if_updating_with_self
    a = Document.create('content' => 'a')
    
    err = assert_raises(RuntimeError) { a.update(a) }
    assert_equal "update fail: #{a.sha} -> #{a.sha} (cannot update with self)", err.message
  end
  
  def test_update_raises_error_if_new_doc_is_a_child_of_self
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.link(b)
    
    err = assert_raises(RuntimeError) { a.update(b) }
    assert_equal "cannot update with a child of self: #{a.sha} -> #{b.sha}", err.message
  end
  
  #
  # link test
  #
  
  def test_link_links_child_to_doc
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.link(b)
  
    assert_equal [b.sha], a.node.children
  end
  
  def test_link_creates_link_association
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    
    a.link(b)
    assert_equal({:create => true, :links => [b.sha]}, repo.associations(a.sha))
  end
  
  def test_link_raises_error_if_unsaved
    child = Document.new
    err = assert_raises(RuntimeError) { doc.link(child) }
    assert_equal "cannot link unless saved", err.message
  end
  
  def test_link_raises_error_if_child_is_unsaved
    child = Document.new('content' => 'child')
    doc.save
    
    err = assert_raises(RuntimeError) { doc.link(child) }
    assert_equal "cannot link to an unsaved document: #{child.inspect}", err.message
  end
  
  def test_link_raises_error_if_document_does_not_belong_to_a_graph
    a = Document.save('content' => 'a')
    b = Document.save('content' => 'b')
    
    err = assert_raises(RuntimeError) { a.link(b) }
    assert_equal "link fail: #{a.sha} -> #{b.sha} (source is not associated with a graph)", err.message
  end
  
  def test_link_raises_error_if_child_belongs_to_a_different_graph
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.link(b)
    
    c = Document.create('content' => 'c')
    d = Document.save('content' => 'd')
    c.link(d)
    
    err = assert_raises(RuntimeError) { b.link(d) }
    assert_equal "link fail: #{b.sha} -> #{d.sha} (different graph heads #{a.sha}/#{c.sha})", err.message
  end
  
  def test_link_raises_error_if_linking_to_self
    a = Document.create('content' => 'a')
    
    err = assert_raises(RuntimeError) { a.link(a) }
    assert_equal "link fail: #{a.sha} -> #{a.sha} (cannot link with self)", err.message
  end
  
  def test_link_raises_error_if_child_is_an_update_to_self
    a = Document.create('content' => 'a')
    b = Document.save('content' => 'b')
    a.update(b)
    
    err = assert_raises(RuntimeError) { a.link(b) }
    assert_equal "cannot link to an update of self: #{a.sha} -> #{b.sha}", err.message
  end
  
  #
  # delete test
  #
  
  def test_delete_raises_error_if_unsaved
    err = assert_raises(RuntimeError) { doc.delete }
    assert_equal "cannot delete unless saved", err.message
  end
  
  #
  # reindex test
  #
  
  def test_reindex_raises_error_unless_saved
    assert_equal false, doc.saved?
    err = assert_raises(RuntimeError) { doc.reindex }
    assert_equal 'cannot reindex unless saved', err.message
  end
end