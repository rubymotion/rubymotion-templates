# NOTE: This class is meant to have zero dependencies on external files (completely self contained),
#       try not to take on external dependencies even if it means that code will be duplicated.
module Motion; module Project
  class Doctor
    def execute silent = true
      if ENV['RM_BYPASS_DOCTOR'] == '1'
        puts "* WARNING: Bypassing `motion doctor`, I hope you know what you're doing!"
        return
      else
        verify_swift
        verify_community_templates
        verify_community_commands
        unless silent
          puts "* INFO: `motion doctor` ran successfully and found no issues. If you are still unable to build your applications, come to the Slack Channel and ask for help there: http://slack.rubymotion.com."
        end
      end
    end

    def raise_error message
        raise <<-S
======================================================================
* ERROR:
#{message}

* NOTE:
If you know what you are doing, Setting the environment variable
RM_BYPASS_DOCTOR=1 will skip RubyMotion's install verifications.
======================================================================
S
    end

    def macos_version
      `sw_vers`.each_line.to_a[1].split(':').last.strip
    rescue
      raise_error "Unable to determine the version of Mac OS X."
    end

    def kill_simulators_command
      "sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService"
    end

    def verify_swift
      return if File.exist?(File.expand_path("/Applications/Xcode.app/Contents/Frameworks/.swift-5-staged"))
      rubymotion_versions = ['6.0', '6.1', '6.2']
      min_macos_version = version_to_i '10.14.4'
      if rubymotion_versions.include?(rubymotion_version) && version_to_i(macos_version) >= min_macos_version
        raise_error <<-S
Mojave #{macos_version}'s Swift 5 runtime was not found in Xcode (or has not been marked as staged).
You must run the following commands to fix Xcode (commands may require sudo):

    cp -r /usr/lib/swift/*.dylib /Applications/Xcode.app/Contents/Frameworks/
    touch /Applications/Xcode.app/Contents/Frameworks/.swift-5-staged

Rerun build after you have ran the commands above.
S
      end
    end

    def verify_community_templates
      if !Dir.exist?(File.expand_path("~/.rubymotion/rubymotion-templates"))
        raise_error "It doesn't look like you have RubyMotion templates downloaded. Please run `motion repo`."
      end

      if !File.exist?(File.expand_path "~/.rubymotion/rubymotion-templates/required-marker-62")
        raise_error "It doesn't look like you have the latest RubyMotion templates downloaded. Please run `motion repo`."
      end
    end

    def verify_community_commands
      if !Dir.exist?(File.expand_path("~/.rubymotion/rubymotion-templates"))
        raise_error "It doesn't look like you have RubyMotion commands downloaded. Please run `motion repo`."
      end

      if !File.exist?(File.expand_path "~/.rubymotion/rubymotion-command/required-marker-62")
        raise_error "It doesn't look like you have the latest RubyMotion commands downloaded. Please run `motion repo`."
      end
    end

    def xcode_versions
      {
        '10.3' => '6.2',
        '10.2' => '6.1',
      }
    end

    def max_xcode_version
      xcode_versions.keys.map do |k|
        version_to_i k
      end.max
    end

    def version_to_i s
      s.to_s.gsub(".", "").to_i
    end

    def compare_xcode_versions version
      version.to_s.gsub(".", "").to_i
    end

    def rubymotion_version
      `motion --version`.each_line.first.strip
    end

    def xcode_version
      xcode_version_data =
        `xcodebuild -version`.each_line
                             .first
                             .strip
                             .gsub('Xcode', '')
                             .split('.')
                             .map(&:strip)
                             .take(2)
                             .join('.')
    end
  end
end; end
