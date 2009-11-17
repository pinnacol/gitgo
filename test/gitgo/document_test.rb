require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/document'

class DocumentTest < Test::Unit::TestCase
  Document = Gitgo::Document
  Actor = Grit::Actor
  
  attr_accessor :author, :date, :doc
  
  def setup
    @author = Grit::Actor.new("John Doe", "john.doe@email.com")
    @date = Time.now
    @doc = Document.new("author" => author, "date" => date)
  end
  
  #
  # parse test
  #
  
  def test_parse_parses_a_document
    str = %q{--- 
author: John Doe <john.doe@email.com>
date: 1252508400 -0600
key: value
--- 
mulit-
  line 
content
}

    doc = Document.parse(str, "1234")
    assert_equal "John Doe", doc.author.name
    assert_equal "john.doe@email.com", doc.author.email
    assert_equal 1252508400, doc.date.to_i
    assert_equal "mulit-\n  line \ncontent\n", doc.content
    assert_equal("value", doc.attributes["key"])
    assert_equal "1234", doc.sha
  end
  
  def test_parse_raises_error_for_invalid_docs
    doc = ""
    err = assert_raises(RuntimeError) { Document.parse(doc) }
    assert_equal "invalid document: (author cannot be nil)\n#{doc}", err.message
    
    doc = "date: 1252508400 -0600"
    err = assert_raises(RuntimeError) { Document.parse(doc) }
    assert_equal "invalid document: (author cannot be nil)\n#{doc}", err.message
    
    doc = "author: John Doe <john.doe@email.com>"
    err = assert_raises(RuntimeError) { Document.parse(doc) }
    assert_equal "invalid document: (date cannot be nil)\n#{doc}", err.message
    
    doc = "--- \ncontent"
    err = assert_raises(RuntimeError) { Document.parse(doc) }
    assert_equal "invalid document: (no attributes specified)\n#{doc}", err.message
  end
  
  #
  # initialize test
  #
  
  def test_initialize_documentation
    doc = Document.new(
      "author" => "John Doe <john.doe@email.com>",
      "date" => "1252508400.123")
    
    assert_equal "John Doe", doc.author.name
    assert_equal 1252508400, doc.date.to_i
    
    author = Grit::Actor.new("John Doe", "john.doe@email.com")
    date = Time.now
  
    doc = Document.new("author" => author, "date" => date)
    assert_equal "John Doe", doc.author.name
    assert_equal date, doc.date
  end
  
  #
  # AGET test
  #
  
  def test_AGET_returns_an_attribute
    doc = Document.new(
      "author" => author,
      "date" => date,
      "key" => "value")
    
    assert_equal author, doc["author"]
    assert_equal date, doc["date"]
    assert_equal "value", doc["key"]
    assert_equal nil, doc["missing"]
  end
  
  #
  # ASET test
  #
  
  def test_ASET_sets_an_attribute
    assert_equal({
      "author" => author,
      "date" => date
    }, doc.attributes)
    
    alt_author = Grit::Actor.new("Jane Doe", "jane.doe@email.com")
    alt_date = date + 1
    
    doc["author"] = alt_author
    doc["date"] = alt_date
    doc["key"] = "value"
    
    assert_equal({
      "author" => alt_author,
      "date" => alt_date,
      "key" => "value"
    }, doc.attributes)
  end
  
  def test_ASET_parses_author_from_string
    doc['author'] =  "Jane Doe <jane.doe@email.com>"
    
    assert_equal "Jane Doe", doc.author.name
    assert_equal "jane.doe@email.com", doc.author.email
  end
  
  def test_ASET_parses_dates_from_numerics
    doc['date'] = 100.1
    assert_equal Time.at(100.1), doc['date']
    
    doc['date'] = 100
    assert_equal Time.at(100), doc['date']
  end
  
  def test_ASET_parses_dates_from_numeric_strings
    doc['date'] = "100.1"
    assert_equal Time.at(100.1), doc['date']
    
    doc['date'] = "100"
    assert_equal Time.at(100), doc['date']
  end
  
  def test_ASET_sets_array_tags_directly
    doc['tags'] =  []
    assert_equal nil, doc["tags"]
    
    doc['tags'] =  [""]
    assert_equal [""], doc["tags"]
    
    doc['tags'] = ["a", "b", "c"]
    assert_equal ["a", "b", "c"], doc["tags"]
  end
  
  def test_ASET_parses_tags_from_string_as_shellwords
    doc['tags'] =  ""
    assert_equal nil, doc["tags"]
    
    doc['tags'] =  "a"
    assert_equal ["a"], doc["tags"]
    
    doc['tags'] = "a b c"
    assert_equal ["a", "b", "c"], doc["tags"]
    
    doc['tags'] = "a 'b c' \"'de'\""
    assert_equal ["a", "b c", "'de'"], doc["tags"]
  end
  
  def test_ASET_nilifies_nil_and_empty_values
    doc['key'] =  ""
    assert_equal nil, doc["key"]
    
    doc['key'] =  []
    assert_equal nil, doc["key"]
    
    doc['key'] =  nil
    assert_equal nil, doc["key"]
    
    doc = Document.new(
      "author" => author, 
      "date" => date, 
      'nil' => nil, 
      'empty' => [], 
      'empty_str' => '', 
      'key' => 'value',
      'int' => 0)
      
    assert_equal nil, doc["nil"]
    assert_equal nil, doc["empty"]
    assert_equal nil, doc["empty_str"]
    assert_equal 'value', doc["key"]
    assert_equal 0, doc["int"]
  end
  
  #
  # each_index test
  #
  
  def test_each_index_yields_indexed_key_value_pairs_to_block
    results = {}
    doc.each_index do |key, value|
      (results[key] ||= []) << value
    end
    
    assert_equal({
      'author' => [author.email],
    }, results)
    
    # more realistic case
    doc = Document.new(
      'author' => author,
      'date' => date,
      'state' => 'open',
      'n' => 1,
      'tags' => ['a', 'b', 'c'],
      'attachments' => ['not', 'indexed']
    )
    
    results = {}
    doc.each_index do |key, value|
      (results[key] ||= []) << value
    end
    
    assert_equal({
      'author' => [author.email],
      'state' => ['open'],
      'tags' => ['a', 'b', 'c'],
    }, results)
  end
  
  #
  # diff test
  #
  
  def test_diff_returns_empty_array_for_same_attrs
    assert_equal({}, doc.diff(doc))
    
    a = doc.merge("key" => "value")
    b = doc.merge("key" => "value")
    
    assert_equal a.attributes, b.attributes
    assert_equal({}, a.diff(b))
  end
  
  def test_diff_returns_changes_in_attrs
    a = doc.merge("changed" => "A", "a_only" => "a", "unchanged" => "value")
    b = doc.merge("changed" => "B", "b_only" => "b", "unchanged" => "value")
    
    assert_equal({'changed' => "A", "a_only" => "a", :b_only => "b"}, a.diff(b))
    assert_equal({'changed' => "B", :a_only => "a", "b_only" => "b"}, b.diff(a))
  end
  
  #
  # to_s test
  #
  
  def test_to_s_formats_doc_as_a_string
    attrs = {
      "author" => Actor.new("John Doe", "john.doe@email.com"),
      "date" => Time.at(1252508400),
      "key" => "value"
    }
    
    expected = %Q{--- 
author: John Doe <john.doe@email.com>
date: 1252508400.0
key: value
--- 
content}

    assert_equal expected, Document.new(attrs, "content").to_s
  end
end