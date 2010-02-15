require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/document'

class DocumentTest < Test::Unit::TestCase
  acts_as_file_test
  
  Actor = Grit::Actor
  Repo = Gitgo::Repo
  Document = Gitgo::Document
  InvalidDocumentError = Document::InvalidDocumentError
  
  attr_accessor :author, :doc
  
  def setup
    super
    
    @author = Grit::Actor.new("John Doe", "john.doe@email.com")
    @current = Document.set_env(lazy_env)
    @doc = Document.new
  end
  
  def teardown
    Document.set_env(@current)
    super
  end
  
  def repo
    @repo ||= Repo.init method_root.path(:repo), :author => author
  end
  
  def lazy_env
    Hash.new do |hash, key|
      if key == Document::REPO
        hash[key] = repo
      else
        nil
      end
    end
  end
  
  #
  # Document.with_env test
  #
  
  def test_with_env_sets_env_during_block
    Document.with_env(:a) do
      assert_equal :a, Document.env
      
      Document.with_env(:z) do
        assert_equal :z, Document.env
      end
      
      assert_equal :a, Document.env
    end
  end
  
  #
  # Document.env test
  #
  
  def test_env_returns_thread_specific_env
    current = Thread.current[Document::ENV]
    begin
      Thread.current[Document::ENV] = :env
      assert_equal :env, Document.env
    ensure
      Thread.current[Document::ENV] = current
    end
  end
  
  def test_env_raises_error_when_no_env_is_in_scope
    current = Thread.current[Document::ENV]
    begin
      Thread.current[Document::ENV] = nil
      
      err = assert_raises(RuntimeError) { Document.env }
      assert_equal "no env in scope", err.message
    ensure
      Thread.current[Document::ENV] = current
    end
  end
  
  #
  # Document.repo test
  #
  
  def test_repo_returns_repo_set_in_env
    Document.with_env(Document::REPO => :repo) do
      assert_equal :repo, Document.repo
    end
  end
  
  def test_repo_raises_error_when_no_repo_is_set_in_env
    Document.with_env({}) do
      err = assert_raises(RuntimeError) { Document.repo }
      assert_equal "no repo in env", err.message
    end
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
  # initialize test
  #
  
  def test_initialize_does_not_parse_attributes
    doc = Document.new('author' => 'Jane Doe <jane.doe@email.com>')
    assert_equal({'author' => 'Jane Doe <jane.doe@email.com>'}, doc.attrs)
  end
  
  def test_initialize_uses_current_env_unless_specified
    Document.with_env(Document::REPO => :repo) do 
      doc = Document.new
      assert_equal :repo, doc.repo
    end
  end
  
  def test_initialize_raises_error_if_no_env_is_specified_or_in_scope
    current = Thread.current[Document::ENV]
    begin
      Thread.current[Document::ENV] = nil
      
      err = assert_raises(RuntimeError) { Document.new }
      assert_equal "no env in scope", err.message
    ensure
      Thread.current[Document::ENV] = current
    end
  end
  
  #
  # repo test
  #
  
  def test_doc_repo_returns_repo_set_in_env
    doc = Document.new({}, {Document::REPO => :repo})
    assert_equal :repo, doc.repo
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
  # save test
  #
  
  def test_save_stores_attrs_and_sets_sha
    doc['key'] = 'value'
    doc.save
    
    attrs = repo.read(doc.sha)
    assert_equal 'value', attrs['key']
  end
  
  def test_save_links_to_parents_to_doc
    a = repo.store('content' => 'a')
    doc['parents'] = [a]
    doc.save
    
    assert_equal [doc.sha], repo.links(a)
  end
  
  def test_save_links_doc_to_children
    b = repo.store('content' => 'b')
    doc['children'] = [b]
    doc.save
    
    assert_equal [b], repo.links(doc.sha)
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
  
  #
  # saved? test
  #
  
  def test_saved_check_returns_true_if_sha_is_set
    assert_equal nil, doc.sha
    assert_equal false, doc.saved?
    
    doc.sha = :sha
    assert_equal true, doc.saved?
  end
end