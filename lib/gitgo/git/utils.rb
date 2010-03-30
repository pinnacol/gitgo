module Gitgo
  class Git
    
    # A set of utility functions split out for ease of testing.
    module Utils
      module_function
      
      # Executes the block having set the env variables.  All ENV variables
      # that start with GIT_ will be removed regardless of whether they are
      # specified in env or not.
      def with_env(env={})
        overrides = {}
        begin
          ENV.keys.each do |key|
            if key =~ /^GIT_/
              overrides[key] = ENV.delete(key)
            end
          end

          env.each_pair do |key, value|
            overrides[key] ||= nil
            ENV[key] = value
          end

          yield
        ensure
          overrides.each_pair do |key, value|
            if value
              ENV[key] = value
            else
              ENV.delete(key)
            end
          end
        end
      end
      
      # Splits a path along slashes into an array, stripping empty strings
      # from each end. An array may be provided in place of path; it will be
      # duplicated before being stripped of nil/empty entries.
      def split(path)
        array = path.kind_of?(String) ? path.split("/") : path.dup
        array.shift if nil_or_empty_string?(array[0])
        array.pop   if nil_or_empty_string?(array[-1])
        array
      end
      
      # Returns true if the object is nil, or empty, and assumes the object is
      # a string (ie that it responds to empty?).
      def nil_or_empty_string?(obj)
        obj.nil? || obj.empty?
      end
      
      # Returns true if the object is nil, or responds to empty and is empty.
      def nil_or_empty?(obj)
        obj.nil? || (obj.respond_to?(:empty?) && obj.empty?)
      end
    end
  end
end