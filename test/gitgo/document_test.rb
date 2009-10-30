require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/document'

class DocumentTest < Test::Unit::TestCase
  Document = Gitgo::Document
  Actor = Grit::Actor
  
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
    assert_equal({"key" => "value"}, doc.attributes(false))
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