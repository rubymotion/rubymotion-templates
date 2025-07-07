module Motion
  module Project
    class Config
      # Allows us to define the config in one file but only
      # execute it when it matches the specified platform.
      def platform(platform_name)
        return unless platform_name.to_sym == template
        yield
      end
    end
  end
end
