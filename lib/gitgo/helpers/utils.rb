module Gitgo
  module Helpers
    module Utils
      module_function
      
      def render(tree, lines=[], indent="", &block)
        lines << "#{indent}<ul>"

        tree.each do |branch|
          case branch
          when Array
            lines << "#{indent}<li>"
            render(branch, lines, indent + "  ", &block)
            lines << "#{indent}</li>"
          when nil
          else
            branch = yield(branch) if block
            lines << "#{indent}<li>#{branch}</li>"
          end
        end

        lines << "#{indent}</ul>"
        lines
      end

      # Flattens an ancestry hash of (parent, [children]) pairs.  For example:
      #
      #   ancestry = {
      #     "a" => ["b"],
      #     "b" => ["c", "d"],
      #     "c" => [],
      #     "d" => ["e"],
      #     "e" => []
      #   }
      #
      #   flatten(ancestry) 
      #   # => {
      #   # "a" => ["a", ["b", ["c"], ["d", ["e"]]]],
      #   # "b" => ["b", ["c"], ["d", ["e"]]],
      #   # "c" => ["c"],
      #   # "d" => ["d", ["e"]],
      #   # "e" => ["e"]
      #   # }
      #
      # Note that the flattened ancestry re-uses the array values, such that
      # modifiying the "b" array will propagate to the "a" ancestry.
      def flatten(ancestry)
        ancestry.each_pair do |parent, children|
          next unless children

          children.collect! {|child| ancestry[child] }
          children.compact!
          children.unshift(parent)
        end
        ancestry
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
    end
  end
end