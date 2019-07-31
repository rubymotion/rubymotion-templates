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

      def run(config, platform)
        self.debug = false
        self.config = config
        self.platform = platform

        # Use of additional entitlements file is currently disabled
        # create_entitlements_file

        codesign
        check_code_signature
        zip_app_file
        notarize
      end

      private

      # The path to the source app bundle which will be notarized
      def app_bundle
        @app_bundle ||= File.dirname(config.app_bundle(platform))
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
        cmd = "codesign -d --entitlements - '#{app_bundle}' > entitlements.xml"
        system cmd
      end

      # Deep codesign the app bundle for notarization
      def codesign
        App.info 'Deep signing executables for notarization', app_bundle

        cmd = []
        opts  = "--timestamp  --sign '#{config.codesign_certificate}' -f --verbose=9 "
        opts += '--deep  --options runtime '

        # Use of additional entitlements file is currently disabled
        # opts += "--entitlements entitlements.xml"

        # Make sure that everything in the bundle is correctly signed
        # especially 3rd party frameworks
        # When not doing this notarization may fail e.g. when using
        # the Sparkle updater CocoaPod (tested with Sparkle pod v1.21)
        # We could turn this into a optional step (e.g. config.force_deep_sign)
        cmd << "find '#{app_bundle}' -type f -exec codesign #{opts} {} +"

        # Sign the full app bundle
        cmd << "codesign #{opts} '#{app_bundle}'"

        sh(cmd)
      end

      # Check the code signature of the app bundle in order to be verbose
      # about errors regarding the signature
      def check_code_signature
        App.info 'Checking code signature… ', app_bundle

        cmd = ["codesign -v --strict --deep --verbose=2 '#{app_bundle}'"]
        cmd << "codesign -d --deep --verbose=2 -r- '#{app_bundle}'"
        cmd << "spctl --assess -vv '#{app_bundle}'"

        sh cmd
      end

      # Zip the app into the target zip file
      def zip_app_file
        App.info 'Zipping .app file to…', release_zip
        cmd = "ditto -c -k --keepParent '#{app_bundle}' '#{release_zip}'"
        sh cmd
      end

      # Submit the zip file for notarization
      def notarize
        App.info 'Submitting for notarization… ', release_zip
        cmd  = 'xcrun altool --notarize-app '
        cmd += "--primary-bundle-id \"#{bundle_id}\" "
        cmd += "--username \"#{developer_userid}\" "
        cmd += "--password \"#{developer_app_password}\" --file '#{release_zip}'"
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
    end
  end
end
