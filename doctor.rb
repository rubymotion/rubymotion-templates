# coding: utf-8
# NOTE: This class is meant to have zero dependencies on external files (completely self contained),
#       try not to take on external dependencies even if it means that code will be duplicated.
module Motion; module Project
  class Doctor
    def execute silent = true
      if ENV['RM_BYPASS_DOCTOR'] == '1'
        puts "* WARNING: Bypassing `motion doctor`, I hope you know what you're doing!"
        return
      else
        @errors = []
        verify_swift
        verify_java
        verify_community_templates
        verify_community_commands
        print_environment_info unless silent

        if @errors.empty?
          unless silent
            puts <<-S
======================================================================
* #{color :green, 'Success!'} `motion doctor` ran successfully and found no issues.

Still need help? Join us on Slack: http://slack.rubymotion.com
======================================================================
S
          end
        else
          puts <<-S
======================================================================
* #{bold(color :red, 'ERROR:')} #{@errors.join("\n")}
* NOTE:
If you know what you are doing, Setting the environment variable
RM_BYPASS_DOCTOR=1 will skip RubyMotion's install verifications.

* HELP:
Find help in our Slack Channel: http://slack.rubymotion.com
======================================================================
S
          exit 1
        end
      end
    end


    def print_environment_info
      puts bold "= ENVIRONMENT INFO ="
      puts "Swift Runtime:        " + (swift_runtime? && swift_staged? ? '✅' : '❌')
      puts "RubyMotion Templates: " + (rubymotion_templates? ? '✅' : '❌')
      puts "RubyMotion Commands:  " + (rubymotion_commands? ? '✅' : '❌')

      puts bold "= RubyMotion ="
      puts "version:      " + rubymotion_version
      puts "osx sdks:     " + `ls /Library/RubyMotion/data/osx`.each_line.map {|l| l.strip}.join(", ")
      puts "ios sdks:     " + `ls /Library/RubyMotion/data/ios`.each_line.map {|l| l.strip}.join(", ")
      if Dir.exist? '/Library/RubyMotion/data/tvos'
        puts "tv sdks:      " + `ls /Library/RubyMotion/data/tvos`.each_line.map {|l| l.strip}.join(", ")
      else
        puts "tv sdks:      " + "(none)"
      end
      if Dir.exist? '/Library/RubyMotion/data/watchos'
        puts "watch sdks:   " + `ls /Library/RubyMotion/data/watchos`.each_line.map {|l| l.strip}.join(", ")
      else
        puts "watch sdks:   " + "(none)"
      end
      puts "android sdks: " + `ls /Library/RubyMotion/data/android`.each_line.map {|l| l.strip}.join(", ")

      puts bold "= xcodebuild ="
      puts `xcodebuild -version`

      puts bold "= clang ="
      puts `clang --version`

      puts bold "= xcode-select ="
      puts "version: " + `xcode-select --version`
      puts "path:    " + xcode_path

      puts bold "= Xcode ="
      puts "osx platform:   " + exec_and_join("ls #{xcode_path}/Platforms/MacOSX.platform/Developer/SDKs/", ", ")
      puts "ios platform:   " + exec_and_join("ls #{xcode_path}/Platforms/iPhoneOS.platform/Developer/SDKs/", ", ")
      puts "tv platform:    " + exec_and_join("ls #{xcode_path}/Platforms/AppleTVOS.platform/Developer/SDKs/", ", ")
      puts "watch platform: " + exec_and_join("ls #{xcode_path}/Platforms/WatchOS.platform/Developer/SDKs/", ", ")

      puts bold "= Android ="
      if Dir.exist? File.expand_path('~/.rubymotion-android/sdk/platforms')
        puts "android sdks:    " + exec_and_join("ls ~/.rubymotion-android/sdk/platforms/", ", ")
      else
        puts "android sdks:    (none)"
      end
      if Dir.exist? File.expand_path('~/.rubymotion-android/ndk')
        puts "android ndk:     " + exec_and_join("cat ~/.rubymotion-android/ndk/source.properties", " ")
      else
        puts "android ndk:     (none)"
      end

      puts bold "= Java ="
      puts `java -version 2>&1`.strip

      puts bold "= MacOS ="
      puts `system_profiler SPSoftwareDataType`.each_line.map {|l| l.strip}.find {|l| l =~ /System Version:/}

      puts bold "= ENV ="
      puts "RUBYMOTION_ANDROID_SDK=" + ENV.fetch("RUBYMOTION_ANDROID_SDK", '')
      puts "RUBYMOTION_ANDROID_NDK=" + ENV.fetch("RUBYMOTION_ANDROID_NDK", '')

      puts bold "= Ruby Manager ="
      puts "rvm:    #{`which rvm`}"
      puts "rbenv:  #{`which rbenv`}"
      puts "chruby: #{`which chruby`}"
      puts "asdf:   #{`which asdf`}"

      puts bold "= Ruby ="
      puts `which ruby`
      puts `ruby -v`

      puts bold "= Homebrew ="
      if `which brew`.empty?
        puts 'Homebrew is not installed.'
      else
        puts `brew --version`
        puts exec_and_join("brew list", ", ")
      end
    rescue => e
      @errors << "Failure in running Doctor#print_environment_info: #{e}"
    end

    def exec_and_join command, delimiter
      `#{command}`.split("\n").map {|l| l.strip }.reject {|l| l.length == 0}.join(delimiter)
    end

    def xcode_path
      @xcode_path ||= `xcode-select --print-path`.strip
    end

    def xcode_frameworks_path
      @xcode_frameworks_path ||= xcode_path.sub('/Developer', '/Frameworks')
    end

    def macos_version
      `sw_vers`.each_line.to_a[1].split(':').last.strip
    rescue
      @errors << "Unable to determine the version of Mac OS X."
      nil
    end

    def kill_simulators_command
      "sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService"
    end

    def verify_swift
      return if swift_staged?

      return unless version_to_i(rubymotion_version) >= version_to_i('6.0')
      return if version_to_i(rubymotion_version) >= version_to_i("7.15") # 7.15 and above no long require this check.

      if swift_runtime?
        @errors << <<-S
Mojave #{macos_version}'s Swift 5 runtime was not marked as staged.
To fix this error, run the following command:

    #{'sudo ' unless File.writable?(xcode_frameworks_path)}touch #{xcode_frameworks_path}/.swift-5-staged
S
      else
        @errors << <<-S
Mojave #{macos_version}'s Swift 5 runtime was not found in Xcode.
To fix this error, run the following commands:

    #{'sudo ' unless File.writable?(xcode_frameworks_path)}cp -r /usr/lib/swift/*.dylib #{xcode_frameworks_path}/
    #{'sudo ' unless File.writable?(xcode_frameworks_path)}touch #{xcode_frameworks_path}/.swift-5-staged
S
      end
    end

    def swift_staged?
      File.exist?(File.expand_path("#{xcode_frameworks_path}/.swift-5-staged"))
    end

    def swift_runtime?
      Dir["#{xcode_frameworks_path}/libswift*.dylib"].any?
    end
    
    def verify_java
      unless java?
        @errors << <<-S
Java Development Kit (JDK) 1.8 is not installed.
To fix this error, download here:

    https://www.oracle.com/java/technologies/javase/javase-jdk8-downloads.html
S      end
    end
    
    def java?
      system('/usr/libexec/java_home -F -v 1.8')
    end

    def verify_community_templates
      unless rubymotion_templates?
        @errors << "It doesn't look like you have RubyMotion templates downloaded. Please run `motion repo`."
      end

      unless File.exist?(File.expand_path "~/.rubymotion/rubymotion-templates/required-marker-62")
        @errors << "It doesn't look like you have the latest RubyMotion templates downloaded. Please run `motion repo`."
      end
    end

    def rubymotion_templates?
      Dir.exist?(File.expand_path("~/.rubymotion/rubymotion-templates"))
    end

    def verify_community_commands
      unless rubymotion_commands?
        @errors << "It doesn't look like you have RubyMotion commands downloaded. Please run `motion repo`."
      end

      unless File.exist?(File.expand_path "~/.rubymotion/rubymotion-command/required-marker-62")
        @errors << "It doesn't look like you have the latest RubyMotion commands downloaded. Please run `motion repo`."
      end
    end

    def rubymotion_commands?
      Dir.exist?(File.expand_path("~/.rubymotion/rubymotion-command"))
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
      @rubymotion_version ||= `motion --version`.strip
    end

    def xcode_version
      `xcodebuild -version`.lines
                           .first
                           .strip
                           .gsub('Xcode', '')
                           .split('.')
                           .map(&:strip)
                           .take(2)
                           .join('.')
    end

    def bold(text)
      "\e[1m#{text}\e[0m"
    end

    def color(c, text)
      code = { red: 31, green: 32 }[c]
      "\e[#{code}m#{text}\e[0m"
    end
  end
end; end
