    class Grit::Actor
      def <=>(another)
        name <=> another.name
      end
    end
    