# frozen_string_literal: true

#
# MIT License
#
# Copyright (c) 2019 Martin Kolb
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'motion/project/builder'

module Motion
  module Project
    # A class for notarizing osx applications
    class Notarizer
      attr_accessor :config, :platform, :debug

      def initialize(config, platform)
        self.debug = false
        self.config = config
        self.platform = platform
      end

      # Submit the app bundle for notarization
      def notarize
        create_entitlements_file

        codesign
        check_code_signature
        zip_app_file
        submit_for_notarization
      end

      # Staple the app bundle and re-zip it
      # to make it acceptable for Gatekeeper
      def staple
        staple_bundle
        zip_app_file
        puts "Your app is now ready for distribution at '#{release_zip}'"
      end

      # Show the notarization history and details on individual
      # notarization items
      def show_history
        clearscreen

        # number and print the history lines
        history.lines.each_with_index do |l, i|
          if i>4 && i < (history.lines.count - 3)
            l = "(#{sprintf("%02d", i-4)}) #{l}"
          else
            l = "     #{l}"
          end
          puts l
        end

        # Let user select a line from the history
        puts "Enter line to see details (x to exit)"
        lno = STDIN.gets
        lno.chomp!
        exit if lno.downcase=='x'

        # Grep the uid of the item and show its details
        uid = history.lines[lno.to_i + 4].match(/[a-zA-Z0-9]{8}\-[a-zA-Z0-9]{4}\-[a-zA-Z0-9]{4}\-[a-zA-Z0-9]{4}\-[a-zA-Z,0-9]{12}/)
        show_notarization_status uid[0]
      end

      private

      # The path to the source app bundle which will be notarized
      def app_bundle
        @app_bundle ||= File.dirname(config.app_bundle(platform))
      end

      # The path to the entitlements file used for signing
      def entitlements_file
        @entitlements_file ||= File.join(config.versionized_build_dir(platform), 'entitlements.xml')
      end

      # The target .zip file which will contain the notarized application bundle
      def release_zip
        @release_zip ||= app_bundle.gsub(/\.app$/, '.zip')
      end

      # The CFBundleIdentifier from the plist as specified in the Rakefile
      def bundle_id
        @bundle_id ||= proc do
          rv = config.identifier
          raise 'Please set app.info_plist[\'CFBundleIdentifier\'] in your Rakefile' if rv.nil?
          rv
        end.call
      end

      # The username of your developer id which is used for notarization
      def developer_userid
        @developer_userid ||= proc do
          rv = config.developer_userid
          raise 'Please set app.developer_userid in your Rakefile' if rv.nil?
          rv
        end.call
      end

      # The password for the specified developer_userid
      # Use @keychain:<name> for keychain items
      # or @env:<variable> for environment variables
      def developer_app_password
        @developer_app_password ||= proc do
          rv = config.developer_app_password
          raise 'Please set app.developer_app_password in your Rakefile! Use @keychain:<name> for keychain items or @env:<variable> for environment variables. See xcrun altool for more help.' if rv.nil?
          rv
        end.call
      end

      # This method creates an entitlements.xml file for the app bundle
      # Currently not in use
      def create_entitlements_file
        App.info 'Creating entitlements.xml file for', app_bundle
        cmd = "codesign -d --entitlements - '#{app_bundle}' > '#{entitlements_file}'"
        system cmd
      end

      # Deep codesign the app bundle for notarization
      def codesign
        App.info 'Deep signing executables for notarization', app_bundle

        cmd = []
        opts  = "--timestamp  --sign '#{config.codesign_certificate}' -f --verbose=9 "
        opts += '--deep  --options runtime '

        # Use of additional entitlements file is currently disabled
        opts += "--entitlements '#{entitlements_file}'"

        # Make sure that everything in the bundle is correctly signed
        # especially 3rd party frameworks
        # When not doing this notarization may fail e.g. when using
        # the Sparkle updater CocoaPod (tested with Sparkle pod v1.21)
        if config.force_deep_sign
          cmd << "find '#{app_bundle}' -type f -exec codesign #{opts} {} +"
        end

        # Sign the full app bundle
        cmd << "codesign #{opts} '#{app_bundle}'"

        sh(cmd)
      end

      # Check the code signature of the app bundle in order to be verbose
      # about errors regarding the signature
      def check_code_signature
        App.info 'Checking code signature… ', app_bundle
        check_valid_on_disk
        puts

        check_hardened_runtime
        puts

        check_spctl
        puts
      end

      def check_valid_on_disk
        result = sh_capture("codesign -v --strict --deep --verbose=2 '#{app_bundle}'")

        text   = 'valid on disk'
        result =~ /#{text}/ ? show_as_success(text) : show_as_failed(text)

        text   = 'satisfies its Designated Requirement'
        result =~ /#{text}/ ? show_as_success(text) : show_as_failed(text)
      end

      def check_hardened_runtime
        result = sh_capture("codesign -d --deep --verbose=2 -r- '#{app_bundle}'")

        text   = 'Timestamp='
        result =~ /#{text}/ ? show_as_success('secure timestamp') : show_as_failed('secure timestamp')

        text   = 'Runtime Version='
        result =~ /#{text}/ ? show_as_success('hardened runtime') : show_as_failed('hardened runtime')
      end

      def check_spctl
        result = sh_capture("spctl --assess -vv '#{app_bundle}'")

        text   = 'accepted'
        result =~ /#{text}/ ? show_as_success(text) : show_as_failed(text)
      end

      # Zip the app into the target zip file
      def zip_app_file
        App.info 'Zipping .app file to…', release_zip
        cmd = "ditto -c -k --keepParent '#{app_bundle}' '#{release_zip}'"
        sh cmd
      end

      # Submit the zip file for notarization
      def submit_for_notarization
        App.info 'Submitting for notarization… ', release_zip
        cmd  = 'xcrun altool --notarize-app '
        cmd += "--primary-bundle-id \"#{bundle_id}\" "
        cmd += "--username '#{developer_userid}' "
        cmd += "--password \"#{developer_app_password}\" --file '#{release_zip}'"
        sh cmd
        puts <<-S
Remember to run

    rake notarize:staple

after notarization was succesful!
To check notarization status run

    rake notarize:history

If notarization fails you might want add the following line to your Rakefile:

    Motion::Project::App.setup do |app|
      ...
      app.force_deep_sign = true
      ...
    end
S
      end

      # Show the status of a notarization item
      # with the given uid
      def show_notarization_status(uid=nil)
        cmd  = 'xcrun altool --notarization-info '
        cmd += "#{uid} "
        cmd += "--username '#{developer_userid}' "
        cmd += "--password '#{developer_app_password}' "

        clearscreen
        puts `#{cmd}`
        STDIN.gets
        show_history
      end

      # Staple the app bundle after successful notarization
      def staple_bundle
        App.info 'Stapling app bundle…', app_bundle
        cmd  = "xcrun stapler staple '#{app_bundle}'"
        sh cmd
      end

      # Helper method for running shell commands
      def sh(cmd)
        cmd = [cmd] unless cmd.is_a? Array
        cmd.each do |c|
          puts "\t'#{c}'" if debug
          system c
        end
      end

      # Helper method for running a shell command and capturing results
      def sh_capture(cmd)
        result = `#{cmd} 2>&1`
        puts result

        result
      end

      def clearscreen
        puts "\033[2J"
      end

      def history
        @history ||= `#{cmd_history}`
      end

      def cmd_history
        cmd  = 'xcrun altool --notarization-history 0 '
        cmd += "--username '#{developer_userid}' "
        cmd += "--password '#{developer_app_password}' "
        cmd
      end

      # show a green checkmark and text
      def show_as_success(text)
        puts "\e[32m\xE2\x9C\x94\e[0m #{text}"
      end

      # show a red X and text
      def show_as_failed(text)
        puts "\e[31m\xE2\x9D\x8C\e[0m #{text}"
      end
    end
  end
end
