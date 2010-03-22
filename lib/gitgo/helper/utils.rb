module Gitgo
  module Helper
    module Utils
      module_function
      
      # Flattens a hash of (parent, [children]) pairs.  For example:
      #
      #   tree = {
      #     "a" => ["b"],
      #     "b" => ["c", "d"],
      #     "c" => [],
      #     "d" => ["e"],
      #     "e" => []
      #   }
      #
      #   flatten(tree) 
      #   # => {
      #   # "a" => ["a", ["b", ["c"], ["d", ["e"]]]],
      #   # "b" => ["b", ["c"], ["d", ["e"]]],
      #   # "c" => ["c"],
      #   # "d" => ["d", ["e"]],
      #   # "e" => ["e"]
      #   # }
      #
      # Note that the flattened hash re-uses the array values, such that
      # modifiying the "b" value will propagate to the "a" value.
      def flatten(tree)
        tree.each_pair do |parent, children|
          next unless children

          children.collect! {|child| tree[child] }
          children.unshift(parent)
        end
        tree
      end

      # Collapses an nested array hierarchy such that nesting is only
      # preserved for existing, and not just potential, branches:
      #
      #   collapse(["a", ["b", ["c"]]])               # => ["a", "b", "c"]
      #   collapse(["a", ["b", ["c"], ["d", ["e"]]]]) # => ["a", "b", ["c"], ["d", "e"]]
      #
      def collapse(array, result=[])
        result << array.at(0)

        if (length = array.length) == 2
          collapse(array.at(1), result)
        else
          1.upto(length-1) do |i|
            result << collapse(array.at(i))
          end
        end

        result
      end
      
      def render(nodes, io=[], list_open='<ul>', list_close='</ul>', item_open='<li>', item_close='</li>', indent='', newline="\n", &block)
        io << indent
        io << list_open
        io << newline

        nodes.each do |node|
          io << indent
          io << item_open
          
          if node.kind_of?(Array)
            io << newline
            render(node, io, list_open, list_close, item_open, item_close, indent + '  ', newline, &block)
            io << newline
            io << indent
          else
            io << (block_given? ? yield(node) : node)
          end
          
          io << item_close
          io << newline
        end

        io << indent
        io << list_close
        io
      end
    end
  end
end