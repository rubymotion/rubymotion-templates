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
      def notarize(wait = false)
        check_app_bundle_exist!
        create_entitlements_file

        codesign
        check_code_signature
        zip_app_file
        submit_for_notarization(wait)
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

        while true do
          # number and print the history lines
          item = 0
          uuids = []

          history.lines.each do |line|
            if line =~ /createdDate:/
              line = "(#{sprintf("%02d", item + 1)}) #{line}"
              item += 1
            else
              uuids << line.match(/id: (?<uuid>.*)/)[:uuid] if line =~ /id:/
              line = "     #{line}"
            end

            puts line
          end

          # Let user select a line from the history
          puts "\nEnter line to see details (x to exit)"
          line_no = STDIN.gets.chomp
          break if line_no.downcase == 'x'

          line_no = line_no.to_i

          if line_no < 1 || line_no > uuids.length
            show_as_failed('Line number out of range')
            puts ''
            next
          end

          show_notarization_status uuids[line_no.to_i - 1]

          puts 'Press <Enter> to continue'
          STDIN.gets
        end
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

      # The Apple ID which is used for notarization
      def developer_apple_id
        @developer_apple_id ||= proc do
          rv = config.developer_apple_id || config.developer_userid
          raise 'Please set app.developer_apple_id to your Apple ID in your Rakefile!' if rv.nil?
          rv
        end.call
      end

      # The password for the specified developer_apple_id
      # Use @keychain:<name> for keychain items
      # or @env:<variable> for environment variables
      def developer_app_password
        @developer_app_password ||= proc do
          rv = config.developer_app_password
          raise 'Please set app.developer_app_password in your Rakefile! Use @keychain:<name> for keychain items or @env:<variable> for environment variables. See xcrun notarytool for more help.' if rv.nil?
          rv
        end.call
      end

      # The Apple ID which is used for notarization
      def developer_team_id
        @developer_team_id ||= proc do
          rv = config.developer_team_id
          raise 'Please set app.developer_team_id to your developer account Team ID in your Rakefile!' if rv.nil?
          rv
        end.call
      end

      # This method creates an entitlements.xml file for the app bundle
      # Currently not in use
      def create_entitlements_file
        App.info 'Creating entitlements.xml file for', app_bundle
        cmd = "codesign -d --xml --entitlements - '#{app_bundle}' > '#{entitlements_file}'"
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

      # Check if the app bundle file exists, otherwise remind the
      # user to run rake build:release
      def check_app_bundle_exist!
        return true if File.exist?(app_bundle)

        show_as_failed("No app bundle found at '#{app_bundle}'! ")
        puts "Please run \n\n\trake build:release \n\nbefore notarizing!"

        exit(1)
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
      def submit_for_notarization(wait = false)
        App.info "Submitting #{'and waiting ' if wait}for notarization… ", release_zip
        sh cmd_notarization_submit(wait)

        puts <<-S

After notarization was succesful, remember to run

    rake notarize:staple

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
      # with the given uuid
      def show_notarization_status(uuid = nil)
        puts ''
        puts `#{cmd_notarization_status(uuid)}`
        puts ''
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
        `#{cmd_history}`
      end

      def cmd_history
        cmd  = 'xcrun notarytool history '
        cmd += "--apple-id '#{developer_apple_id}' "
        cmd += "--password '#{developer_app_password}' "
        cmd += "--team-id '#{developer_team_id}' "
        cmd
      end

      def cmd_notarization_status(uuid = nil)
        cmd  = 'xcrun notarytool info '
        cmd += "#{uuid} "
        cmd += "--apple-id '#{developer_apple_id}' "
        cmd += "--password '#{developer_app_password}' "
        cmd += "--team-id '#{developer_team_id}'"
        cmd
      end

      def cmd_notarization_submit(wait)
        cmd  = 'xcrun notarytool submit '
        cmd += "--apple-id '#{developer_apple_id}' "
        cmd += "--password \"#{developer_app_password}\" "
        cmd += "--team-id '#{developer_team_id}' "
        cmd += "--wait " if wait
        cmd += "'#{release_zip}'"
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
