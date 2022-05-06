# encoding: utf-8

# Copyright (c) 2012, HipByte SPRL and contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'socket'

module Motion; module Project

  class AndroidManifest < Hash

    attr_reader :name

    def initialize(name = 'manifest')
      @name = name
      @children = []
    end

    def add_child(name, properties = {}, &block)
      nested = AndroidManifest.new(name)
      nested.merge!(properties)
      block.call(nested) if block
      @children << nested
      nested
    end

    def child(name, &block)
      child = children(name).first
      block.call(child) if block
      child
    end

    def children(name)
      @children.select { |c| c.name == name }
    end

    def to_xml(depth = 0)
      str = "#{'  ' * depth}<#{@name} "

      str << map do |key, value|
        v = evaluate(value)
        # Some properties fail to compile if they are nil, so we clean them
        v.nil? ? nil : "#{key}=\"#{v}\""
      end.compact.join(' ')

      if @children.empty?
        str << " />\n"
      else
        str << " >\n"

        # children
        str << @children.map { |c| c.to_xml(depth + 1) }.join('')

        xml_lines_name = @name == "manifest" ? nil : @name
        str << App.config.manifest_xml_lines(xml_lines_name).map { |line| "#{'  ' * (depth + 1) }#{line}\n" }.join('')

        str << "#{'  ' * depth}</#{@name}>\n"
      end
      str
    end

    private

    def evaluate(value)
      if value.is_a? Proc
        value.call
      else
        value
      end
    end

  end

  class AndroidConfig < Config
    register :android

    variable :sdk_path, :ndk_path, :package, :main_activity, :sub_activities,
             :api_version, :target_api_version, :archs, :assets_dirs, :icon,
             :logs_components, :version_code, :version_name, :permissions, :features,
             :optional_features, :services, :application_class, :manifest, :theme,
             :support_libraries, :multidex, :main_dex_list

    # Non-public.
    attr_accessor :vm_debug_logs, :libs

    def initialize(project_dir, build_mode)
      super
      @main_activity = 'MainActivity'
      @sub_activities = []
      @archs = ['armv7']
      @assets_dirs = [File.join(project_dir, 'assets')]
      @vendored_projects = []
      @permissions = []
      @features = []
      @optional_features = []
      @services = []
      @manifest_entries = {}
      @release_keystore_path = nil
      @release_keystore_alias = nil
      @version_code = '1'
      @version_name = '1.0'
      @application_class = nil
      @vm_debug_logs = false
      @multidex = false
      @libs = Hash.new([])
      @manifest = AndroidManifest.new
      construct_manifest

      if path = ENV['RUBYMOTION_ANDROID_SDK']
        @sdk_path = File.expand_path(path)
      end
      if path = ENV['RUBYMOTION_ANDROID_NDK']
        @ndk_path = File.expand_path(path)
      end

      if Motion::Project::Config.starter?
        self.assets_dirs << File.join(File.dirname(__FILE__), 'launch_image')
        self.api_version = '28'
      end
    end

    def construct_manifest
      manifest = @manifest

      manifest['xmlns:android'] = 'http://schemas.android.com/apk/res/android'
      manifest['package'] = -> { package }

      manifest['android:versionCode'] = -> { "#{version_code}" }
      manifest['android:versionName'] = -> { "#{version_name}" }

      manifest.add_child('uses-sdk') do |uses_sdk|
        uses_sdk['android:minSdkVersion'] = -> { "#{api_version}" }
        uses_sdk['android:targetSdkVersion'] = -> { "#{target_api_version}" }
      end

      manifest.add_child('application') do |application|
        application['android:label'] = -> { "#{name}" }
        application['android:debuggable'] = -> { "#{development? ? 'true' : 'false'}" }
        application['android:icon'] = -> { icon ? "@drawable/#{icon}" : nil }
        application['android:name'] = -> { application_class ? application_class : nil }
        application['android:theme'] = -> { "#{theme}" }
        application.add_child('activity') do |activity|
          activity['android:name'] = -> { main_activity }
          activity['android:label'] = -> { name }
          activity.add_child('intent-filter') do |filter|
            filter.add_child('action', 'android:name' => 'android.intent.action.MAIN')
            filter.add_child('category', 'android:name' => 'android.intent.category.LAUNCHER')
          end
        end
      end
    end

    def theme
      @theme ||= begin
        if Motion::Util::Version.new(target_api_version) >= Motion::Util::Version.new(21)
          "@android:style/Theme.Material.Light"
        else
          "@android:style/Theme.Holo"
        end
      end
    end

    def validate
      if !sdk_path or !File.exist?("#{sdk_path}/platforms")
        App.fail "app.sdk_path should point to a valid Android SDK directory. Run 'motion android-setup-legacy' to install the latest SDK version."
      end

      if !ndk_path or !File.exist?("#{ndk_path}/platforms")
        App.fail "app.ndk_path should point to a valid Android NDK directory. Run 'motion android-setup' to install the latest NDK version."
      end

      if api_version == nil or !File.exist?("#{sdk_path}//platforms/android-#{api_version}")
        App.fail "The Android SDK installed on your system does not support " + (api_version == nil ? "any API level. Run 'motion android-setup' to install the latest API level." : "API level #{api_version}") + ". Run 'motion android-setup --api_version=#{api_version}' to install it."
      end

      if !File.exist?("#{ndk_path}/platforms/android-#{api_version_ndk}")
        App.fail "The Android NDK installed on your system does not support API level #{api_version}. Run 'motion android-setup' to install a more recent NDK version."
      end

      super
    end

    def zipalign_path
      @zipalign ||= begin
        ary = Dir.glob(File.join(sdk_path, 'build-tools/*/zipalign')).sort
        if ary.empty?
          path = File.join(sdk_path, 'tools/zipalign')
          unless File.exist?(path)
            App.fail "Can't locate `zipalign' tool. Make sure you properly installed the Android Build Tools package and try again."
          end
          path
        else
          ary.last
        end
      end
    end

    def package
      # Legalize package names so they don't include /[^a-zA-Z0-9_]/
      # See https://developer.android.com/guide/topics/manifest/manifest-element.html
      App.fail "Please use only ASCII letters in `app.name'." unless name.ascii_only?
      @package ||= 'com.yourcompany' + '.' + name.downcase.gsub(/\s/, '').gsub(/[^a-zA-Z0-9_]/, '_')
    end

    def package_path
      package.gsub('.', '/')
    end

    def latest_api_version
      @latest_api_version ||= begin
        versions = Dir.glob(sdk_path + '/platforms/android-*').sort.map do |path|
          md = File.basename(path).match(/\d+$/)
          md ? md[0] : nil
        end.compact
        return nil if versions.empty?
        numbers = versions.map { |x| x.to_i }
        vers = numbers.max
        vers.to_s
      end
    end

    def api_version
      @api_version ||= latest_api_version
    end

    def target_api_version
      @target_api_version ||= latest_api_version
    end

    def support_libraries
      @support_libraries ||= []
    end

    def versionized_build_dir
      sep = spec_mode ? 'Testing' : build_mode_name
      File.join(build_dir, sep + '-' + api_version)
    end

    def build_tools_dir
      @build_tools_dir ||= Dir.glob(sdk_path + '/build-tools/*').sort { |x, y| File.basename(x) <=> File.basename(y) }.max
    end

    def build_tools_version
      @build_tools_version ||= Motion::Util::Version.new(build_tools_dir.match(/(\d)+\.(\d)+\.(\d)+/))
    end

    def aab_path
      File.join(versionized_build_dir, name + '.aab')
    end

    def apk_path
      File.join(versionized_build_dir, name + '.apk')
    end

    def ndk_toolchain_bin_dir
      @ndk_toolchain_bin_dir ||= begin
        path = File.join(ndk_path, "toolchains/llvm/prebuilt/darwin-x86_64/bin")
        App.fail "Can't locate a proper NDK toolchain (paths tried: #{paths.join(' ')}). Please install NDK toolchain using `motion android-setup' command." unless path
        path
      end
    end

    def cc
      File.join(ndk_toolchain_bin_dir, 'clang')
    end

    def cxx
      File.join(ndk_toolchain_bin_dir, 'clang++')
    end

    def common_arch(arch)
      case arch
        when /^arm/
          arch.start_with?('arm64') ? 'arm64' : 'arm'
        when 'x86'
          arch
        else
          raise "Invalid arch `#{arch}'"
      end
    end

    def toolchain_flags(arch)
      case common_arch(arch)
        when 'arm'
          "-marm -target armv7-none-linux-androideabi#{api_version_ndk} "
        when 'arm64'
          "-marm -target arm64-v8a-linux-androideabi#{api_version_ndk}"
        when 'x86'
          "-target i686-none-linux-android#{api_version_ndk} "
        else
          raise "invalid arch #{arch}"
      end
    end

    def asflags(arch)
      archflags = ''
      case arch
        when /^arm/
          if arch == 'armv5te'
            archflags << "-march=armv5te "
          elsif arch == 'armv7'
            archflags << "-march=armv7a -mfpu=vfpv3-d16 "
          end
        when 'x86'
          # Nothing.
        else
          raise "Invalid arch `#{arch}'"
      end
      "-no-canonical-prefixes #{toolchain_flags(arch)} #{archflags}"
    end

    def api_version_ndk
      '30'
    end

    def cflags(arch)
      archflags = case arch
        when 'armv5te'
          "-mtune=xscale"
      end
      "#{asflags(arch)} #{archflags} -MMD -MP -fpic -ffunction-sections -funwind-tables -fexceptions -fstack-protector -fno-rtti -fno-strict-aliasing -O0 -g3 -fno-omit-frame-pointer -DANDROID -isysroot \"#{ndk_path}/sysroot\" -Wformat -Werror=format-security -Wno-unknown-attributes"
    end

    def cxxflags(arch)
      "#{cflags(arch)} -std=c++14 -I\"#{ndk_path}/sources/cxx-stl/stlport/stlport\""
    end

    def appt_flags
      aapt_flags = ""
      aapt_flags << "--no-version-vectors" if build_tools_version >= Motion::Util::Version.new(27)
      aapt_flags
    end

    def payload_library_filename
      "lib#{payload_library_name}.so"
    end

    def payload_library_name
      'payload'
    end

    def ldflags(arch)
      "#{toolchain_flags(arch)} -Wl,-soname,#{payload_library_filename} -shared -isysroot \"#{ndk_path}/sysroot\" -no-canonical-prefixes -Wl,--no-undefined -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -O0 -g3"
    end

    def versioned_datadir
      "#{motiondir}/data/android/#{api_version}"
    end

    def versioned_arch_datadir(arch)
      "#{versioned_datadir}/#{arch}"
    end

    def ldlibs_pre(arch)
      # The order of the libraries matters here.
      # -B controls where the linker will look for the crtbegin_so/crtend files
      "-B\"#{ndk_path}/platforms/android-#{api_version_ndk}/arch-#{common_arch(arch)}/usr/lib\" -L\"#{ndk_path}/platforms/android-#{api_version_ndk}/arch-#{common_arch(arch)}/usr/lib\" -lc++ -lc -lm -llog -L\"#{versioned_arch_datadir(arch)}\" -lrubymotion-static"
    end

    def ldlibs_post(arch)
      "-L#{ndk_path}/sources/cxx-stl/llvm-libc++/libs/#{armeabi_directory_name(arch)} -latomic"
    end

    def armeabi_directory_name(arch)
      case arch
        when 'armv5te'
          'armeabi'
        when 'armv7'
          'armeabi-v7a'
        when 'arm64-v8a', 'x86'
          arch
        else
          raise "Invalid arch `#{arch}'"
      end
    end

    def bin_exec(name)
      result = File.join(motiondir, 'bin', name)

      if (name == 'ruby')
        ruby_android = File.join(motiondir, 'bin', 'ruby-android')
        if File.exist? ruby_android
          result = ruby_android
        end
      end

      result
    end

    def kernel_path(arch)
      File.join(versioned_arch_datadir(arch), "kernel-#{arch}.bc")
    end

    def clean_project
      super
      vendored_bs_files(false).each do |path|
        if File.exist?(path)
          App.info 'Delete', path
          FileUtils.rm_f path
        end
      end
    end

    attr_reader :vendored_projects

    def vendor_project(opt)
      jar = opt.delete(:jar)
      App.fail "Expected `:jar' key/value pair in `#{opt}'" unless jar
      res = opt.delete(:resources)
      manifest = opt.delete(:manifest)
      filter = opt.delete(:filter)
      native = opt.delete(:native) || []
      App.fail "Expected `:manifest' key/value pair when `:resources' is given" if res and !manifest
      App.fail "Expected `:resources' key/value pair when `:manifest' is given" if manifest and !res
      App.fail "Unused arguments: `#{opt}'" unless opt.empty?

      package = nil
      if manifest
        line = `/usr/bin/xmllint --xpath '/manifest/@package' \"#{manifest}\"`.strip
        App.fail "Given manifest `#{manifest}' does not have a `package' attribute in the top-level element" if $?.to_i != 0
        package = line.match(/package=\"(.+)\"$/)[1]
      end
      @vendored_projects << { :jar => jar, :resources => res, :manifest => manifest, :package => package, :native => native, :filter => filter }
    end

    def vendored_bs_files(create=true)
      @vendored_bs_files ||= begin
        vendored_projects.map do |proj|
          jar_file = proj[:jar]
          bs_file = File.join(versionized_build_dir, File.basename(jar_file) + '.bridgesupport')
          if create and (!File.exist?(bs_file) or File.mtime(jar_file) > File.mtime(bs_file))
            App.info 'Create', bs_file
            filter_args =
              if ary = proj[:filter]
                ary.map { |x| "-f \"#{x}\"" }.join(' ')
              else
                ''
              end
            sh "\"#{bin_exec('android/gen_bridge_metadata')}\" -o \"#{bs_file}\" #{filter_args} \"#{jar_file}\""
          end
          bs_file
        end
      end
    end

    def logs_components
      @logs_components ||= begin
        ary = []
        ary << package_path + ':I'
        %w(AndroidRuntime chromium dalvikvm Bundle art).each do |comp|
          ary << comp + ':E'
        end
        ary
      end
    end

    def ctags_files
      ctags_files = vendored_bs_files + files.flatten
      ctags_files + Dir.glob(File.join(versioned_datadir, 'BridgeSupport/*.bridgesupport')).sort
    end

    def ctags_config_file
      File.join(motiondir, 'data', 'bridgesupport-android-ctags.cfg')
    end

    attr_reader :manifest_entries

    def manifest_entry(toplevel_element=nil, element, attributes)
      if toplevel_element
        App.fail "toplevel element must be either nil or `application'" unless toplevel_element == 'application'
      end
      elems = (@manifest_entries[toplevel_element] ||= [])
      elems << { :name => element, :attributes => attributes }
    end

    def manifest_xml_lines(toplevel_element)
      (@manifest_entries[toplevel_element] or []).map do |elem|
        name = elem[:name]
        attributes = elem[:attributes]
        attributes_line = attributes.to_a.map do |key, val|
          key = case key
            when :name
              'android:name'
            when :value
              'android:value'
            else
              key
          end
          "#{key}=\"#{val}\""
        end.join(' ')
        "<#{name} #{attributes_line}/>"
      end
    end

    attr_reader :release_keystore_path, :release_keystore_alias

    def release_keystore(path, alias_name)
      @release_keystore_path = path
      @release_keystore_alias = alias_name
    end

    def version(code, name)
      @version_code = code
      @version_name = name
    end

    def local_repl_port
      @local_repl_port ||= begin
        ports_file = File.join(versionized_build_dir, 'repl_ports.txt')
        if File.exist?(ports_file)
          File.read(ports_file)
        else
          local_repl_port = TCPServer.new('localhost', 0).addr[1]
          File.open(ports_file, 'w') { |io| io.write(local_repl_port.to_s) }
          local_repl_port
        end
      end
    end
  end
end; end
