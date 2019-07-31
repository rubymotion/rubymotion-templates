# encoding: utf-8
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

module Motion; module Project
  class Notarizer

    attr_accessor :config, :platform, :debug

    def run(config, platform)
      self.debug = false
      self.config = config
      self.platform = platform

      create_entitlements_file
      codesign
      check_code_signature
      zip_app_file
      notarize
    end

    private

    def app_bundle
      @app_bundle ||= File.dirname(self.config.app_bundle(self.platform))
    end

    def release_zip
      @release_zip ||= app_bundle.gsub(/\.app$/, '.zip')
    end

    def bundle_id
      @bundle_id ||= proc do
        rv = config.identifier
        raise 'Please set app.info_plist[\'CFBundleIdentifier\'] in your Rakefile' if rv.nil?
        rv
      end.call
    end

    def developer_userid
      @developer_userid ||= proc do
        rv = config.developer_userid
        raise 'Please set app.developer_userid in your Rakefile' if rv.nil?
        rv
      end.call
    end

    def altool_keychain_item
      @altool_keychain_item ||= proc do
        rv = config.altool_keychain_item
        raise 'Please set app.altool_keychain_item in your Rakefile!' if rv.nil?
        rv
      end.call
    end

    def create_entitlements_file
      App.info "Creating entitlements.xml file for", app_bundle
      cmd = "codesign -d --entitlements - '#{app_bundle}' > entitlements.xml"
      system cmd
    end

    def codesign
      App.info "Deep signing executables for notarization", app_bundle

      cmd = []
      opts  = "--timestamp  --sign '#{config.codesign_certificate}' -f --verbose=9 "
      opts += "--deep  --options runtime "
      opts += "--entitlements entitlements.xml"

      cmd << "find '#{app_bundle}' -type f -exec codesign #{opts} {} +"
      cmd << "codesign #{opts} '#{app_bundle}'"

      sh(cmd)
    end

    def check_code_signature
      App.info "Checking code signature… ", app_bundle

      cmd = ["codesign -v --strict --deep --verbose=2 '#{app_bundle}'"]
      cmd << "codesign -d --deep --verbose=2 -r- '#{app_bundle}'"
      cmd << "spctl --assess -vv '#{app_bundle}'"

      sh cmd
    end

    def zip_app_file
      App.info "Zipping .app file to…", release_zip
      cmd = "ditto -c -k --keepParent '#{app_bundle}' '#{release_zip}'"
      sh cmd
    end

    def notarize
      App.info "Submitting for notarization… ", release_zip
      cmd  = 'xcrun altool --notarize-app '
      cmd += "--primary-bundle-id \"#{bundle_id}\" "
      cmd += "--username \"#{developer_userid}\" "
      cmd += "--password \"@keychain:#{altool_keychain_item}\" --file '#{release_zip}'"
      sh cmd
    end

    def sh(cmd)
      cmd = [cmd] unless cmd.is_a? Array
      cmd.each do |c|
        puts "\t'#{c}'" if self.debug
        system c
      end
    end
  end
end; end
