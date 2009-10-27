require File.dirname(__FILE__) + "/../test_helper"

class RenderTest < Test::Unit::TestCase

  def render(array, prefix="", indent=false, lines=[])
    head = tail = nil
    if array[-1].kind_of?(Integer)      # this had a merge extracted
      head = "-"
      tail = "-#{array.pop}"
    end
    
    if array[0].kind_of?(Integer)    # this is an extracted merge
      tail = "#{tail} (#{array.shift})"
    end
    
    lines << "#{prefix}#{head}#{array.shift}#{tail}\n"
    
    prefix += " " if indent
    array.each do |item|
      render(item, prefix, array.length > 1, lines)
    end
    lines
  end
  
  def assert_output_equal(a, b, msg=nil)
    a = a[1..-1] if a[0] == ?\n
    if a == b
      assert true
    else
      flunk %Q{
#{msg}
==================== expected output ====================
#{whitespace_escape(a)}
======================== but was ========================
#{whitespace_escape(b)}
=========================================================
}
    end
  end
  
  def whitespace_escape(str)
    str.to_s.gsub(/\s/) do |match|
      case match
      when "\n" then "\\n\n"
      when "\t" then "\\t"
      when "\r" then "\\r"
      when "\f" then "\\f"
      else match
      end
    end
  end
    
  # a-b-c
  def test_render_single_thread
    expected = [:a, [:b, [:c]]]
    assert_output_equal %q{
a
b
c
}, render(expected).join
  end
  
  # a-b
  #  -c
  def test_render_shallow_threads
    expected = [:a, [:b], [:c]]
    assert_output_equal %q{
a
b
c
}, render(expected).join
  end
  
  # a-b-c
  #  -d-e
  def test_render_threads
    expected = [:a, [:b, [:c]], [:d, [:e]]]
    assert_output_equal %q{
a
b
 c
d
 e
}, render(expected).join
  end
  
  # a-b-c-d
  #  -e-f-g
  def test_render_deep_threads
    expected = [:a, [:b, [:c, [:d]]], [:e, [:f, [:g]]]]
    assert_output_equal %q{
a
b
 c
 d
e
 f
 g
}, render(expected).join
  end
  
  # a-b
  #  -c-d-e
  def test_render_mixed_threads
    expected = [:a, [:b], [:c, [:d, [:e]]]]
    assert_output_equal %q{
a
b
c
 d
 e
}, render(expected).join
  end
  
  # a-b-c
  #  -d-c
  def test_merge_threads
    expected = [:a, [:b, 0], [:d, 0], [0, :c]]
    assert_output_equal %q{
a
-b-0
-d-0
c (0)
}, render(expected).join
  end

  # a-b-c
  #  -d-c
  def test_unmerged_threads_for_comparison
    expected = [:a, [:b, [:c]], [:d, [:c]]]
    assert_output_equal %q{
a
b
 c
d
 c
}, render(expected).join
  end
  
  # a-b-c-e-f
  #  -d-c-e-f
  def test_merge_continuing_thread
    expected = [:a, [:b, 0], [:d, 0], [0, :c, [:e, [:f]]]]
    assert_output_equal %q{
a
-b-0
-d-0
c (0)
 e
 f
}, render(expected).join
  end
  
  # a-b-c-e-f
  #  -d-c-e-f
  def test_unmerged_continuing_thread_for_comparison
    expected = [:a, [:b, [:c, [:e, [:f]]]], [:d, [:c, [:e, [:f]]]]]
    assert_output_equal %q{
a
b
 c
 e
 f
d
 c
 e
 f
}, render(expected).join
  end

  # a-b-c
  #  -d-c
  #  -e
  def test_merged_mixed_threads
    expected = [:a, [:b, 0], [:d, 0], [0, :c], [:e]]
    assert_output_equal %q{
a
-b-0
-d-0
c (0)
e
}, render(expected).join
  end
  
  # a-b-c
  #  -d-c
  #  -e
  def test_unmerged_mixed_threads_for_comparison
    expected = [:a, [:b, [:c]], [:d, [:c]], [:e]]
    assert_output_equal %q{
a
b
 c
d
 c
e
}, render(expected).join
  end
    
  # a-b-c-e-f
  #  -d-c-e-f
  #  -g-h
  def test_merge_mixed_continuing_thread
    expected = [:a, [:b, 0], [:d, 0], [0, :c, [:e, [:f]]], [:g, [:h]]]
    assert_output_equal %q{
a
-b-0
-d-0
c (0)
 e
 f
g
 h
}, render(expected).join
  end

  # a-b-c-e-f
  #  -d-c-e-f
  #  -g-h
  def test_unmerged_mixed_continuing_thread_for_comparison
    expected = [:a, [:b, [:c, [:e, [:f]]]], [:d, [:c, [:e, [:f]]]], [:g, [:h]]]
    assert_output_equal %q{
a
b
 c
 e
 f
d
 c
 e
 f
g
 h
}, render(expected).join
  end
    
  # a-b-c-d-e
  #    -f-g-e
  #  -h-i
  def test_merge_on_a_thread
    expected = [:a, [:b, [:c, [:d, 0]], [:f, [:g, 0]], [0, :e]], [:h, [:i]]]
    assert_output_equal %q{
a
b
 c
  -d-0
 f
  -g-0
 e (0)
h
 i
}, render(expected).join
  end
  
  # a-b-c-d-e
  #    -f-g-e
  #  -h-i
  def test_unmerged_on_a_thread_for_comparison
    expected = [:a, [:b, [:c, [:d, [:e]]], [:f, [:g, [:e]]]], [:h, [:i]]]
    assert_output_equal %q{
a
b
 c
  d
  e
 f
  g
  e
h
 i
}, render(expected).join
  end
  
  # a-b-c-d-e-f-g
  #    -h-e-f-g
  #  -i-e-f-g
  def test_multiple_merge
    expected = [:a, [:b, [:c, [:d, 0]], [:h, 0]], [:i, 0], [0, :e, [:f, [:g]]]]
    assert_output_equal %q{
a
b
 c
  -d-0
 -h-0
-i-0
e (0)
 f
 g
}, render(expected).join
  end

  # a-b-c-d-e-f-g
  #    -h-e-f-g
  #  -i-e-f-g
  def test_unmerged_multiple_merge_for_comparison
    expected = [:a, [:b, [:c, [:d, [:e, [:f, [:g]]]]], [:h, [:e, [:f, [:g]]]]], [:i, [:e, [:f, [:g]]]]]
    assert_output_equal %q{
a
b
 c
  d
  e
  f
  g
 h
  e
  f
  g
i
 e
 f
 g
}, render(expected).join
  end
    
  # a-b-c-d-e
  #  -f-c-d-e
  #  -g-d-e
  def test_in_and_out_merge
    expected =[:a, [:b, 0], [:f, 0], [0, :c, 1], [:g, 1], [1, :d, [:e]]]
    assert_output_equal %q{
a
-b-0
-f-0
-c-1 (0)
-g-1
d (1)
 e
}, render(expected).join
  end

  # a-b-c-d-e
  #  -f-c-d-e
  #  -g-d-e
  def test_unmerged_in_and_out_merge_for_comparison
    expected = [:a, [:b, [:c, [:d, [:e]]]], [:f, [:c, [:d, [:e]]]], [:g, [:d, [:e]]]]
    assert_output_equal %q{
a
b
 c
 d
 e
f
 c
 d
 e
g
 d
 e
}, render(expected).join
  end
end