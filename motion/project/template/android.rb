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

require 'motion/project/app'

App = Motion::Project::App
App.template = :android

require 'motion/project'
require 'motion/project/template/android/config'
require 'motion/project/repl_launcher'

desc "Create an application package file (.apk)"
task :build do
  # Prepare build directory.
  app_build_dir = App.config.versionized_build_dir
  mkdir_p app_build_dir

  # Support libraries.
  supported_libraries = {
    'android-support-v4' => {
      'jar' => 'android-support-v4.jar'
    },
    'android-support-v13' => {
      'jar' => 'android-support-v13.jar'
    },
    'android-support-v17-leanback' => {
      'jar' => '/libs/android-support-v17-leanback.jar',
      'res' => true
    },
    'android-support-v7-appcompat' => {
      'jar' => '/libs/android-support-v7-appcompat.jar',
      'res' => true,
      'dependencies' => ['android-support-v4']
    },
    'android-support-v7-cardview' => {
      'jar' => '/libs/android-support-v7-cardview.jar',
      'res' => true
    },
    'android-support-v7-gridlayout' => {
      'jar' => '/libs/android-support-v7-gridlayout.jar',
      'res' => true
    },
    'android-support-v7-mediarouter' => {
      'jar' => '/libs/android-support-v7-mediarouter.jar',
      'res' => true
    },
    'android-support-v7-palette' => {
      'jar' => '/libs/android-support-v7-palette.jar'
    },
    'android-support-v7-recyclerview' => {
      'jar' => '/libs/android-support-v7-recyclerview.jar'
    },
    'android-support-annotations' => {
      'jar' => '/android-support-annotations.jar'
    },
    'google-play-services' => {
      'path' => '/google/google_play_services/libproject/google-play-services_lib',
      'jar' => '/libs/google-play-services.jar'
    },
    'android-support-multidex' => {
      'jar' => '/library/libs/android-support-multidex.jar'
    }
  }
  support_libraries = []
  App.config.support_libraries << 'android-support-multidex' if App.config.multidex
  extras_path = File.join(App.config.sdk_path, 'extras')
  App.config.support_libraries.each do |support_library|
    if library_config = supported_libraries.fetch(support_library, false)
      dependencies = library_config.fetch('dependencies', [])
      dependencies.each do |dependency|
        support_libraries << dependency
      end
      support_libraries << support_library
    else
      App.fail "We do not support `#{support_library}`. Supported libraries are : #{supported_libraries.keys.join(',')}"
    end
  end
  support_libraries.uniq.each do |support_library|
    library_config = supported_libraries.fetch(support_library)
    library_relative_path = library_config.fetch('path', support_library.split('-'))
    library_path = File.join(extras_path, library_relative_path)
    jar_path = File.join(library_path, library_config['jar'])
    if File.exist?(jar_path)
      vendor_config = { :jar => jar_path }
      if library_config.fetch('res', false)
        vendor_config[:manifest] = File.join(library_path, 'AndroidManifest.xml')
        vendor_config[:resources] = File.join(library_path, 'res')
      end
      App.config.vendor_project(vendor_config)
    else
      App.fail "We couldn't find `#{support_library}. Use #{File.join(App.config.sdk_path, 'tools', 'android')} to install it."
    end
  end

  # Permissions.
  permissions = Array(App.config.permissions)
  if App.config.development?
    # In development mode, we need the INTERNET permission in order to create
    # the REPL socket.
    permissions |= ['android.permission.INTERNET']
  end
  permissions.each do |permission|
    permission = "android.permission.#{permission.to_s.upcase}" if permission.is_a?(Symbol)
    App.config.manifest.add_child('uses-permission', 'android:name' => "#{permission}")
  end

  # Multidex support
  if App.config.multidex && App.config.application_class.nil?
    App.config.manifest.child('application')['android:name'] = "android.support.multidex.MultiDexApplication"
  end

  # Features.
  App.config.features.each do |feature|
    App.config.manifest.child('application').add_child('uses-feature', 'android:name' => "#{feature}")
  end

  # Optional features.
  App.config.optional_features.each do |feature|
    App.config.manifest.child('application').add_child('uses-feature', 'android:name' => "#{feature}", 'android:required' => 'false')
  end

  # Sub-activities.
  (App.config.sub_activities.uniq - [App.config.main_activity]).each do |activity|
    App.config.manifest.child('application').add_child('activity') do |sub_activity|
      if activity.is_a? Hash
        sub_activity['android:name'] = "#{activity[:name]}"
        sub_activity['android:label'] = "#{activity[:label] || activity[:name]}"
      else
        sub_activity['android:name'] = "#{activity}"
        sub_activity['android:label'] = "#{activity}"
      end
      sub_activity['android:parentActivityName'] = -> { "#{App.config.main_activity}" }

      sub_activity.add_child('meta-data') do |meta|
        meta['android:name'] = 'android.support.PARENT_ACTIVITY'
        meta['android:value'] = -> { "#{App.config.main_activity}" }
      end
    end
  end

  # Services.
  App.config.services.each do |service|
    App.config.manifest.child('application').add_child('service', 'android:name' => "#{service}", 'android:exported' => 'false')
  end

  # Generate AndroidManifest.xml.
  android_manifest_txt = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
  android_manifest_txt << App.config.manifest.to_xml

  android_manifest = File.join(app_build_dir, 'AndroidManifest.xml')
  if !File.exist?(android_manifest) or File.read(android_manifest) != android_manifest_txt
    App.info 'Create', android_manifest
    File.open(android_manifest, 'w') { |io| io.write(android_manifest_txt) }
  end

  # Create R.java files.
  java_dir = File.join(app_build_dir, 'java')
  java_app_package_dir = File.join(java_dir, *App.config.package.split(/\./))
  mkdir_p java_app_package_dir
  r_bs = File.join(app_build_dir, 'R.bridgesupport')
  android_jar = "#{App.config.sdk_path}/platforms/android-#{App.config.target_api_version}/android.jar"
  grab_directories = lambda do |ary|
    ary.flatten.select do |dir|
      File.exist?(dir) and File.directory?(dir)
    end
  end
  assets_dirs = grab_directories.call(App.config.assets_dirs)
  aapt_assets_flags = assets_dirs.map { |x| '-A "' + x + '"' }.join(' ')
  resources_dirs = grab_directories.call(App.config.resources_dirs)
  all_resources = (resources_dirs + App.config.vendored_projects.map { |x| x[:resources] }.compact)
  aapt_resources_flags = all_resources.map { |x| '-S "' + x + '"' }.join(' ')
  r_java_mtime = Dir.glob(java_dir + '/**/R.java').sort.map { |x| File.mtime(x) }.max
  bs_files = []
  classes_changed = false
  if !r_java_mtime or all_resources.any? { |x| Dir.glob(x + '/**/*').sort.any? { |y| File.mtime(y) > r_java_mtime } }
    packages_list = App.config.vendored_projects.map { |x| x[:package] }.compact.join(':')
    extra_packages = packages_list.empty? ? '' : '--extra-packages ' + packages_list
    sh "\"#{App.config.build_tools_dir}/aapt\" package -f -M \"#{android_manifest}\" #{aapt_assets_flags} #{aapt_resources_flags} -I \"#{android_jar}\" -m -J \"#{java_dir}\" #{extra_packages} --auto-add-overlay --max-res-version #{App.config.target_api_version} #{App.config.appt_flags}"

    r_java = Dir.glob(java_dir + '/**/R.java').sort
    classes_dir = File.join(app_build_dir, 'classes')
    mkdir_p classes_dir

    r_java.each do |java_path|
      sh "/usr/bin/javac -d \"#{classes_dir}\" -classpath #{classes_dir} -sourcepath \"#{java_dir}\" -target 1.5 -bootclasspath \"#{android_jar}\" -encoding UTF-8 -g -source 1.5 \"#{java_path}\""
    end

    r_classes = Dir.glob(classes_dir + '/**/R\$*[a-z]*.class').sort.map { |c| "'#{c}'" }
    sh "RUBYOPT='' \"#{App.config.bin_exec('android/gen_bridge_metadata')}\" #{r_classes.join(' ')} -o \"#{r_bs}\" "

    classes_changed = true
  end
  bs_files << r_bs if File.exist?(r_bs)

  objs_build_dirs = []
  libpayload_subpaths = []
  libpayload_paths = []
  gdbserver_subpaths = []
  native_libs = []

  App.config.archs.uniq.each do |arch|
    # Compile Ruby files.
    ruby = App.config.bin_exec('ruby')
    bs_files += Dir.glob(File.join(App.config.versioned_datadir, 'BridgeSupport/*.bridgesupport')).sort
    bs_files += App.config.vendored_bs_files
    ruby_bs_flags = bs_files.map { |x| "--uses-bs \"#{x}\"" }.join(' ')
    objs_build_dir = File.join(app_build_dir, 'obj', 'local', App.config.armeabi_directory_name(arch))
    objs_build_dirs << objs_build_dir
    kernel_bc = App.config.kernel_path(arch)
    ruby_objs_changed = false

    @compiler = []
    build_file = Proc.new do |files_build_dir, ruby_path, job|
      ruby_obj = File.join(objs_build_dir, File.expand_path(ruby_path) + '.' + arch + '.o')
      init_func = "MREP_" + `/bin/echo \"#{File.expand_path(ruby_obj)}\" | /usr/bin/openssl sha1`.strip
      if !File.exist?(ruby_obj) \
          or File.mtime(ruby_path) > File.mtime(ruby_obj) \
          or File.mtime(ruby) > File.mtime(ruby_obj) \
          or File.mtime(kernel_bc) > File.mtime(ruby_obj)
        App.info 'Compile', ruby_path
        asm = ruby_obj + '.s'
        FileUtils.mkdir_p(File.dirname(asm))
        @compiler[job] ||= {}
        ruby_arch = 'x86_64'
        @compiler[job][arch] ||= IO.popen("/usr/bin/env VM_PLATFORM=android VM_KERNEL_PATH=\"#{kernel_bc}\" VM_OPT_LEVEL=\"#{App.config.opt_level}\" arch -#{ruby_arch} \"#{ruby}\" #{ruby_bs_flags} --project_dir \"#{Dir.pwd}\" --emit-llvm-fast \"\"", "r+")
        @compiler[job][arch].puts "#{asm}\n#{init_func}\n#{ruby_path}"
        @compiler[job][arch].gets # wait to finish compilation
        sh "#{App.config.cc} #{App.config.asflags(arch)} -c \"#{asm}\" -o \"#{ruby_obj}\""
        ruby_objs_changed = true
      end
      [ruby_obj, init_func]
    end

    # Resolve file dependencies.
    if App.config.detect_dependencies == true
      App.config.dependencies = Motion::Project::Dependency.new(App.config.files - App.config.exclude_from_detect_dependencies, App.config.dependencies).run
    end

    parallel = Motion::Project::ParallelBuilder.new(objs_build_dir, build_file)
    parallel.files = App.config.ordered_build_files
    parallel.files += App.config.spec_files if App.config.spec_mode
    parallel.run

    # terminate compiler process
    @compiler.each do |item|
      next unless item
      item.each do |k, v|
        v.puts "quit"
      end
    end

    ruby_objs = parallel.objects

    FileUtils.touch(objs_build_dir) if ruby_objs_changed

    # Generate payload main file.
    payload_c_txt = <<EOS
// This file has been generated. Do not modify by hands.
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <jni.h>
#include <assert.h>
#include <android/log.h>
extern "C" {
    void rb_vm_register_native_methods(void);
    bool rb_vm_init(const char *app_package, const char *rm_env, const char *rm_version, JNIEnv *env);
    void *rb_vm_top_self(void);
    void rb_rb2oc_exc_handler(void);
EOS
    App.config.custom_init_funcs.each do |init_func|
      payload_c_txt << "    void #{init_func}(void);\n"
    end
    ruby_objs.each do |_, init_func|
      payload_c_txt << <<EOS
    void *#{init_func}(void *rcv, void *sel);
EOS
    end
    payload_c_txt  << "int rm_repl_port = #{App.config.local_repl_port};\n"
    payload_c_txt << <<EOS
}
extern bool ruby_vm_debug_logs;
extern "C"
jint
JNI_OnLoad(JavaVM *vm, void *reserved)
{
    __android_log_write(ANDROID_LOG_DEBUG, "#{App.config.package_path}", "Loading payload");
    JNIEnv *env = NULL;
    if (vm->GetEnv((void **)&env, JNI_VERSION_1_6) != JNI_OK) {
	return -1;
    }
    assert(env != NULL);
    #{App.config.vm_debug_logs ? 'ruby_vm_debug_logs = true;' : ''}
    rb_vm_init("#{App.config.package_path}", "#{App.config.rubymotion_env_value}", "#{Motion::Version}", env);
    void *top_self = rb_vm_top_self();
EOS
    App.config.custom_init_funcs.each do |init_func|
      payload_c_txt << <<EOS
    env->PushLocalFrame(32);
    #{init_func}();
    env->PopLocalFrame(NULL);
EOS
    end
    ruby_objs.each do |ruby_obj, init_func|
      payload_c_txt << <<EOS
    try {
	env->PushLocalFrame(32);
	#{init_func}(top_self, NULL);
	env->PopLocalFrame(NULL);
    }
    catch (...) {
	__android_log_write(ANDROID_LOG_ERROR, "#{App.config.package_path}", "Uncaught exception when initializing `#{File.basename(ruby_obj).sub(/\.bc$/, '')}' scope -- aborting");
	return -1;
    }
EOS
    end
    payload_c_txt << <<EOS
    rb_vm_register_native_methods();
    __android_log_write(ANDROID_LOG_DEBUG, "#{App.config.package_path}", "Loaded payload");
    return JNI_VERSION_1_6;
  }
EOS
    payload_c = File.join(app_build_dir, 'jni/payload-' + arch + '.cpp')
    if !File.exist?(payload_c) or File.read(payload_c) != payload_c_txt
      mkdir_p File.dirname(payload_c)
      File.open(payload_c, 'w') { |io| io.write(payload_c_txt) }
    end

    # Compile and link payload library.
    libs_abi_subpath = "lib/#{App.config.armeabi_directory_name(arch)}"
    libpayload_subpath = "#{libs_abi_subpath}/#{App.config.payload_library_filename}"
    libpayload_subpaths << libpayload_subpath
    libpayload_path = "#{app_build_dir}/#{libpayload_subpath}"
    libpayload_paths << libpayload_path
    payload_o = File.join(File.dirname(payload_c), 'payload.o')
    if !File.exist?(libpayload_path) \
        or ruby_objs_changed \
        or File.mtime(File.join(App.config.versioned_arch_datadir(arch), "librubymotion-static.a")) > File.mtime(libpayload_path) \
        or File.mtime(payload_c) > File.mtime(payload_o)
      App.info 'Create', libpayload_path
      FileUtils.mkdir_p(File.dirname(libpayload_path))
      sh "#{App.config.cc} #{App.config.cflags(arch)} -c \"#{payload_c}\" -o \"#{payload_o}\""
      sh "#{App.config.cxx} #{App.config.ldflags(arch)} \"#{payload_o}\" #{ruby_objs.map { |o, _| "\"" + o + "\"" }.join(' ')} -o \"#{libpayload_path}\" #{App.config.ldlibs_pre(arch)} #{App.config.libs[App.config.armeabi_directory_name(arch)].join(' ')} #{App.config.ldlibs_post(arch)} -v"
    end

    # copy over libc++_shared.so to the build directory for apk bundling
    sh "cp \"#{App.config.ndk_path}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so\" \"#{app_build_dir}/#{libs_abi_subpath}/libc++_shared.so\""
    sh "cp -R ./assets/ #{File.join app_build_dir, "obj", "assets/"}"
    libpayload_subpaths << "#{libs_abi_subpath}/libc++_shared.so"

    # Copy the gdb server.
    gdbserver_subpath = "#{libs_abi_subpath}/gdbserver"
    gdbserver_subpaths << gdbserver_subpath
    gdbserver_path = "#{app_build_dir}/#{gdbserver_subpath}"
    if !File.exist?(gdbserver_path)
      App.info 'Create', gdbserver_path
      sh "/usr/bin/install -p #{App.config.ndk_path}/prebuilt/android-#{App.config.common_arch(arch)}/gdbserver/gdbserver #{File.dirname(gdbserver_path)}"
    end

    # Install native shared libraries.
    App.config.vendored_projects.map { |x| x[:native] }.compact.flatten.each do |native_lib_src|
      next unless native_lib_src.include?(App.config.armeabi_directory_name(arch))
      native_lib_subpath = "#{libs_abi_subpath}/#{File.basename(native_lib_src)}"
      native_lib_path = "#{app_build_dir}/#{native_lib_subpath}"
      native_libs << native_lib_subpath
      if !File.exist?(native_lib_path) \
          or File.mtime(native_lib_src) > File.mtime(native_lib_path)
        App.info 'Create', native_lib_path
        sh "/usr/bin/install -p #{native_lib_src} #{File.dirname(native_lib_path)}"
      end
    end

    # Create the gdb config file.
    gdbconfig_path = "#{app_build_dir}/#{libs_abi_subpath}/gdb.setup"
    if !File.exist?(gdbconfig_path)
      App.info 'Create', gdbconfig_path
      File.open(gdbconfig_path, 'w') do |io|
        io.puts <<EOS
set solib-search-path #{libs_abi_subpath}:obj/local/#{App.config.armeabi_directory_name(arch)}
source "#{App.config.ndk_path}/prebuilt/common/gdb/common.setup"
directory "#{App.config.ndk_path}/platforms/android-#{App.config.api_version_ndk}/arch-#{App.config.common_arch(arch)}/usr/include" jni "#{App.config.ndk_path}/sources/cxx-stl/system"
EOS
      end
    end
  end

  # Create a build/libs -> build/lib symlink (important for ndk-gdb).
  Dir.chdir(app_build_dir) { ln_s 'lib', 'libs' unless File.exist?('libs') }

  # Create a build/jni/Android.mk file (important for ndk-gdb).
  File.open("#{app_build_dir}/jni/Android.mk", 'w') do |io|
    io.puts "APP_ABI := " + App.config.archs.map { |x| App.config.armeabi_directory_name(x) }.join(' ')
  end

  # Create java files based on the classes map files.
  java_classes = {}
  Dir.glob(objs_build_dirs[0] + '/**/*.map', File::FNM_DOTMATCH).sort.each do |map|
    txt = File.read(map)
    current_class = nil
    txt.each_line do |line|
      if md = line.match(/^([^\s]+)\s*:\s*([^\s]+)\s*<([^>]*)>$/)
        current_class = java_classes[md[1]]
        if current_class
          # Class is already exported, make sure the super classes match.
          if current_class[:super] != md[2]
            if current_class[:super] != '$blank$'
              App.fail "Class `#{md[1]}' already defined with a different super class (`#{current_class[:super]}')"
            else
              current_class[:super] = md[2]
            end
          end
        else
          # Export a new class.
          infs = md[3].split(',').map { |x| x.strip }
          current_class = { :super => md[2], :methods => [], :interfaces => infs }
          java_classes[md[1]] = current_class
        end
      elsif md = line.match(/^\t(.+)$/)
        if current_class == nil
          $stderr.puts "Method declaration outside class definition"
          exit 1
        end
        method_line = md[1]
        add_method = false
        if method_line.include?('{')
          # A method definition (ex. a constructor), always include it.
          if !current_class[:methods].include?(method_line)
            add_method = true
          end
        else
          # Strip 'public native X' (where X is the return type).
          ary = method_line.split(/\s+/)
          if ary[0] == 'public' and ary[1] == 'native'
            method_line2 = ary[3..-1].join(' ')
            # Make sure we are not trying to declare the same method twice.
            if current_class[:methods].all? { |x| x.index(method_line2) != x.size - method_line2.size }
              add_method = true
            end
          else
            # Probably something else (what could it be?).
            add_method = true
          end
        end
        current_class[:methods] << method_line if add_method
      else
        $stderr.puts "Ignoring line: #{line}"
      end
    end
  end
  App.config.files.flatten.map { |x| File.dirname(x) }.uniq.each do |path|
    # Load extension files (any .java file inside the same directory of a .rb file).
    Dir.glob(File.join(path, "*.java")).sort.each do |java_ext|
      class_name = File.basename(java_ext).sub(/\.java$/, '')
      klass = java_classes[class_name]
      unless klass
        # Convert underscore-case to CamelCase (ex. my_service -> MyService).
        class_name = class_name.split('_').map { |e| e.capitalize }.join
        klass = java_classes[class_name]
      end
      App.fail "Java file `#{java_ext}' extends a class that was not discovered by the compiler" unless klass
      (klass[:extensions] ||= "").concat(File.read(java_ext))
    end
  end
  java_classes.each do |name, klass|
    klass_super = klass[:super]
    klass_super = 'java.lang.Object' if klass_super == '$blank$'
    if !klass_super.include?('.') and !java_classes.key?(klass_super)
      # Super class does not exist, skipping...
      next
    end
    java_file_txt = ''
    java_file_txt << <<EOS
// This file has been generated automatically. Do not edit.
package #{App.config.package};
import #{App.config.package}.*;
import com.rubymotion.*;
EOS
    java_file_txt << "public class #{name} extends #{klass_super.gsub('$', '.')}"
    if klass[:interfaces].size > 0
      java_file_txt << " implements #{klass[:interfaces].join(', ')}"
    end
    java_file_txt << " {\n"
    if ext = klass[:extensions]
      java_file_txt << ext.gsub(/^/m, "\t")
    end
    klass[:methods].each do |method|
      java_file_txt << "\t#{method}\n"
    end
    if name == App.config.application_class or (App.config.application_class == nil and name == App.config.main_activity)
      # We need to insert code to load the payload library. It has to be done either in the main activity class or in the custom application class (if provided), as the later will be loaded first.
      java_file_txt << "\tstatic {\n\t\tjava.lang.System.loadLibrary(\"#{App.config.payload_library_name}\");\n\t}\n"
    end

    if name == App.config.application_class && App.config.multidex
      # If a custom application class has been provided and multidex is enabled, we have to enable multidex implementing this method
      java_file_txt << <<EOS
\t@Override
\tprotected void attachBaseContext(android.content.Context context) {
\t\tsuper.attachBaseContext(context);
\t\tandroid.support.multidex.MultiDex.install(this);
\t}
EOS
    end
    java_file_txt << "}\n"
    java_file = File.join(java_app_package_dir, name + '.java')
    if !File.exist?(java_file) or File.read(java_file) != java_file_txt
      File.open(java_file, 'w') { |io| io.write(java_file_txt) }
    end
  end

  # Compile java files.
  vendored_jars = App.config.vendored_projects.map { |x| x[:jar] }
  vendored_jars += [File.join(App.config.versioned_datadir, 'rubymotion.jar')]
  classes_dir = File.join(app_build_dir, 'classes')
  mkdir_p classes_dir
  class_path = [classes_dir, "#{App.config.sdk_path}/tools/support/annotations.jar", *vendored_jars].map { |x| "\"#{x}\"" }.join(':')
  java_paths = []
  Dir.glob(File.join(app_build_dir, 'java', '**', '*.java')).sort.each do |java_path|
    paths = java_path.split('/')
    paths[paths.index('java')] = 'classes'
    paths[-1].sub!(/\.java$/, '.class')
    java_class_path = paths.join('/')

    class_name = File.basename(java_path, '.java')
    if !java_classes.key?(class_name) and class_name != 'R'
      # This .java file is not referred in the classes map, so it must have been created in the past. We remove it as well as its associated .class file (if any).
      rm_rf java_path
      rm_rf java_class_path
      classes_changed = true
      next
    end

    if !File.exist?(java_class_path) or File.mtime(java_path) > File.mtime(java_class_path)
      java_paths << java_path
    end
  end
  compile_java_file = Proc.new do |classes_dir, java_path|
    App.info 'Create', java_path if Rake.application.options.trace
    sh "/usr/bin/javac -d \"#{classes_dir}\" -classpath #{class_path} -sourcepath \"#{java_dir}\" -target 1.5 -bootclasspath \"#{android_jar}\" -encoding UTF-8 -g -source 1.5 \"#{java_path}\""
    classes_changed = true
  end
  parallel = Motion::Project::ParallelBuilder.new(classes_dir, compile_java_file)
  parallel.files = java_paths
  parallel.run

  # Generate the dex file.
  if App.config.multidex
    FileUtils.rm Dir.glob(File.join(app_build_dir, '*.dex')).sort
    main_dex_list = <<-EOS
android/support/multidex/BuildConfig.class
android/support/multidex/MultiDex$V14.class
android/support/multidex/MultiDex$V19.class
android/support/multidex/MultiDex$V4.class
android/support/multidex/MultiDex.class
android/support/multidex/MultiDexApplication.class
android/support/multidex/MultiDexExtractor$1.class
android/support/multidex/MultiDexExtractor.class
android/support/multidex/ZipUtil$CentralDirectory.class
android/support/multidex/ZipUtil.class
#{App.config.package}/#{App.config.main_activity}.class
EOS
    main_dex_list << "#{App.config.package}/#{App.config.application_class}.class\n" if App.config.application_class
    main_dex_list << App.config.main_dex_list if App.config.main_dex_list
    main_dex_list_path = File.join(app_build_dir, 'main-dex-list.txt')
    File.open(main_dex_list_path, 'w') { |io| io.write(main_dex_list) }
    App.info 'Create', 'dex files'
    dx_binary_location = App.config.sdk_path + "/build-tools/30.0.0" + "/dx"
    sh "\"#{dx_binary_location}\" -JXmx2048m --dex --no-strict --multi-dex --main-dex-list \"#{main_dex_list_path}\" --output \"#{app_build_dir}\" \"#{classes_dir}\" \"#{App.config.sdk_path}/tools/support/annotations.jar\" #{vendored_jars.compact.map{ |x| "'#{x}'" }.join(' ')}"
  else
    dex_classes = File.join(app_build_dir, 'classes.dex')
    if !File.exist?(dex_classes) \
        or File.mtime(App.config.project_file) > File.mtime(dex_classes) \
        or classes_changed \
        or vendored_jars.any? { |x| File.mtime(x) > File.mtime(dex_classes) }
      App.info 'Create', dex_classes
      dx_binary_location = App.config.sdk_path + "/build-tools/30.0.0" + "/dx"
      sh "\"#{dx_binary_location}\" -JXmx2048m --dex --no-strict --incremental --output \"#{dex_classes}\" \"#{classes_dir}\" \"#{App.config.sdk_path}/tools/support/annotations.jar\" #{vendored_jars.compact.map{ |x| "'#{x}'" }.join(' ')}"
    end
  end

  keystore = nil
  if App.config.development?
    # Create the debug keystore if needed.
    keystore = File.expand_path('~/.android/debug.keystore')
    unless File.exist?(keystore)
      App.info 'Create', keystore
      FileUtils.mkdir_p(File.expand_path('~/.android'))
      sh "/usr/bin/keytool -genkeypair -alias androiddebugkey -keypass android -keystore \"#{keystore}\" -storepass android -dname \"CN=Android Debug,O=Android,C=US\" -validity 9999"
    end
  else
    keystore = App.config.release_keystore_path
    App.fail "app.release_keystore(path, alias_name) must be called when doing a release build" unless keystore
  end

  dex_files = Dir.glob(File.join(app_build_dir, '*.dex')).sort

  if App.config.development?
    archive = App.config.apk_path
  else
    archive = App.config.aab_path
  end
  if !File.exist?(archive) \
      or dex_files.any? { |f| File.mtime(f) > File.mtime(archive) } \
      or File.mtime(android_manifest) > File.mtime(archive) \
      or libpayload_paths.any? { |x| File.mtime(x) > File.mtime(archive) } \
      or assets_dirs.any? { |x| File.mtime(x) > File.mtime(archive) } \
      or resources_dirs.any? { |x| File.mtime(x) > File.mtime(archive) } \
      or native_libs.any? { |x| File.mtime("#{app_build_dir}/#{x}") > File.mtime(archive) }
    App.info 'Create', archive
    if App.config.development?
      # Generate the APK file.
      sh "\"#{App.config.build_tools_dir}/aapt\" package -f -M \"#{android_manifest}\" #{aapt_assets_flags} #{aapt_resources_flags} -I \"#{android_jar}\" -F \"#{archive}\" --auto-add-overlay  --max-res-version #{App.config.target_api_version} #{App.config.appt_flags}"
      Dir.chdir(app_build_dir) do
        [*dex_files.map { |f| File.basename(f) }, *libpayload_subpaths, *native_libs, *gdbserver_subpaths].each do |file|
          line = "\"#{App.config.build_tools_dir}/aapt\" add -f \"#{File.basename(archive)}\" \"#{file}\""
          line << " > /dev/null" unless Rake.application.options.trace
          sh line
        end
      end

      App.info 'Align', archive
      sh "\"#{App.config.zipalign_path}\" -f 4 \"#{archive}\" \"#{archive}-aligned\""
      sh "/bin/mv \"#{archive}-aligned\" \"#{archive}\""

      App.info 'Sign', archive
      line = "\"#{App.config.build_tools_dir}/apksigner\" sign --ks-pass pass:android --ks \"#{keystore}\" --ks-key-alias androiddebugkey \"#{archive}\""
      line << " >& /dev/null" unless Rake.application.options.trace
      sh line
    else
      FileUtils.rm(archive) if File.exist?(archive)
      # Generate the AAB file.
      sh "\"#{App.config.build_tools_dir}/aapt2\" compile --dir resources -o \"#{File.join(app_build_dir, 'obj', 'res.zip')}\""
      sh "\"#{App.config.build_tools_dir}/aapt2\" link --proto-format #{aapt_assets_flags}  -o \"#{File.join(app_build_dir, 'obj', 'linked.zip')}\" -I \"#{android_jar}\" --manifest \"#{android_manifest}\" --java src \"#{File.join(app_build_dir, 'obj', 'res.zip')}\" --auto-add-overlay"
      Dir.chdir(File.join(app_build_dir, 'obj')) do
        sh "/usr/bin/jar xf linked.zip resources.pb AndroidManifest.xml res"
        mkdir_p "dex"
        mkdir_p "manifest"
        sh "/bin/cp AndroidManifest.xml manifest"
        [*dex_files.map { |f| File.basename(f) }].each do |file|
          line = "/bin/cp \"../#{file}\" dex/"
          line << " > /dev/null" unless Rake.application.options.trace
          sh line
        end
        [*libpayload_subpaths, *native_libs].each do |file|
          mkdir_p File.dirname(file)
          line = "/bin/cp -R \"../#{file}\" \"#{file}\""
          line << " > /dev/null" unless Rake.application.options.trace
          sh line
        end
        sh "/usr/bin/jar cMf base.zip manifest dex res lib assets resources.pb"
      end
      sh "bundletool build-bundle --modules=\"#{File.join(app_build_dir, 'obj', 'base.zip')}\" --output=\"#{archive}\""

      App.info 'Sign', archive
      sh "/usr/bin/jarsigner -sigalg SHA256withRSA -digestalg SHA-256 -keystore \"#{keystore}\" \"#{archive}\" \"#{App.config.release_keystore_alias}\" -tsa http://timestamp.digicert.com"
    end
  end

  $bs_files = bs_files
end

desc "Create an application package file (.apk) for release (Google Play)"
task :release do
  App.config_without_setup.build_mode = :release
  App.config_without_setup.distribution_mode = true
  Rake::Task["build"].invoke
end

def adb_mode_flag(mode)
  case mode
    when :emulator
      '-e'
    when :device
      "-s #{device_id}"
    else
      raise
  end
end

def adb_path
  "#{App.config.sdk_path}/platform-tools/adb"
end

def install_apk(mode)
  App.info 'Install', App.config.apk_path

  if mode == :device
    App.fail "Could not find a USB-connected device" if device_id.empty?
  else
    App.fail "Could not find emulator" if device_id.empty?
  end

  device_version = device_api_version(device_id)
  app_api_version = App.config.api_version
  app_api_version = app_api_version.to_i
  if device_version < app_api_version
    App.fail "Cannot install an app built for API version #{App.config.api_version} on a device running API version #{device_version}"
  end

  # Because adb always returns exit code 0 even if the command failed, we need
  # to check for the presence of the string "Failure" to detect if the
  # installation was successful
  line = "\"#{adb_path}\" #{adb_mode_flag(mode)} install -r \"#{App.config.apk_path}\" 2>&1"
  IO.popen(line) do |io|
    output = io.read
    if output.include?('Failure')
      puts output
      App.fail "Could not install application on the device"
    elsif Rake.application.options.trace
      puts output
    end
  end
end

def device_api_version(device_id)
  api_version = `"#{adb_path}" -d -s "#{device_id}\" shell getprop ro.build.version.sdk`
  if $?.exitstatus == 0
    api_version.to_i
  else
    App.fail "Could not retrieve the API version for the USB-connected device. Make sure that the cable is properly connected and that the computer is authorized on the device to use USB debugging. Alternatively, try running the `#{adb_path} -d logcat' command in another terminal then run this task again."
  end
end

def device_id
  @device_id ||= `\"#{adb_path}\" -d devices| awk 'NR==1{next} length($1)>0{printf $1; exit}'`
end

def start_activity(path, mode)
  line = "\"#{adb_path}\" #{adb_mode_flag(mode)} shell am start -a android.intent.action.MAIN -n #{path}"
  line << " > /dev/null" unless Rake.application.options.trace
  sh line
end

def run_apk(mode)
  activity_path = "#{App.config.package}/.#{App.config.main_activity}"
  if ENV['debug']
    Dir.chdir(App.config.versionized_build_dir) do
      App.info 'Debug', App.config.apk_path
      start_activity(activity_path, mode)
      at_exit { system("/bin/stty echo") } # make sure we set terminal echo back in case ndk-gdb messes it up
      trap('INT') {} # do nothing on ^C, since we wand ndk-gdb to handle it
      line = "\"#{App.config.ndk_path}/ndk-gdb\" #{adb_mode_flag(mode)} --adb=\"#{adb_path}\" -x \"#{App.config.motiondir}/lib/motion/project/template/android/gdb.setup\""
      line << " --verbose" if Rake.application.options.trace
      sh line
    end
  else
    # Clear logs.
    sh "\"#{adb_path}\" #{adb_mode_flag(mode)} logcat -c"
    # Start main activity.
    App.info 'Start', activity_path
    start_activity(activity_path, mode)
    # Show logs.
    adb_logs = "\"#{adb_path}\" #{adb_mode_flag(mode)} logcat -s #{App.config.logs_components.join(' ')}"
    adb_logs_pid = spawn adb_logs
    if App.config.spec_mode
      # In spec mode, we print the logs until we determine that the app is no longer alive.
      while true
        break unless `\"#{adb_path}\" #{adb_mode_flag(mode)} shell ps`.include?(App.config.package)
        sleep 1
      end
      Process.kill('KILL', adb_logs_pid)
    else
      # Enable port forwarding for the REPL socket.
      local_tcp = begin
        # Generate a random TCP port.
        socket = TCPServer.new('localhost', 0)
        port = socket.addr[1]
        socket.close
        begin
          TCPSocket.new('localhost', port)
        rescue Errno::ECONNREFUSED
          port
        else
          '33333'
        end
      end
      remote_tcp = App.config.local_repl_port

      # Show logs in a child process.
      at_exit do
        # Kill the logcat process.
        Process.kill('KILL', adb_logs_pid)
        # Kill the app (if it's still active).
        if `\"#{adb_path}\" -d shell ps`.include?(App.config.package)
          sh "\"#{adb_path}\" #{adb_mode_flag(mode)} shell am force-stop #{App.config.package}"
        end
        # Disable the forwarding.
        sh "\"#{adb_path}\" #{adb_mode_flag(mode)} forward --remove tcp:#{local_tcp}"
        # Set the terminal echo back.
        system("/bin/stty echo")
      end
      sh "\"#{adb_path}\" #{adb_mode_flag(mode)} forward tcp:#{local_tcp} tcp:#{remote_tcp}"
      # Determine architecture of device.
      arch = `\"#{adb_path}\" #{adb_mode_flag(mode)} shell getprop ro.product.cpu.abi`.strip
      case arch
        when 'x86'
        when /^armeabi/
          arch = 'armv5te'
        when 'arm64-v8a'
          if App.config.archs.include?(arch)
          elsif App.config.archs.include?('armv7')
            arch = 'armv7'
          else
            arch = 'armv5te'
          end
        else
          App.fail "Unrecognized device architecture `#{arch}' (expected arm or x86)."
      end

      # Launch the REPL.
      repl_launcher = Motion::Project::REPLLauncher.new({
        "kernel-path" => App.config.kernel_path(arch),
        "local-port" => local_tcp,
        "device-hostname" => "0.0.0.0",
        "platform" => "android",
        "verbose" => App::VERBOSE,
        "bs_files" => $bs_files
      })

      sh repl_launcher.launch_cmd
    end
  end
end

namespace 'emulator' do
  desc "Install the app in the emulator"
  task :install => :'emulator:build' do
    install_apk(:emulator)
  end

  desc "Start the app's main intent in the emulator"
  task :start do
    unless ENV["skip_build"]
      Rake::Task["emulator:build"].invoke
      Rake::Task["emulator:install"].invoke
    end
    run_apk(:emulator)
  end

  task :build do
    App.config.archs = ['x86', 'arm64-v8a'] # Build x86 and arm binary for emulators (arm added for M1/M2 macs)
    Rake::Task["build"].invoke
  end
end

namespace 'device' do
  desc "Install the app in the device"
  task :install do
    install_apk(:device)
  end

  desc "Start the app's main intent in the device"
  task :start do
    run_apk(:device)
  end
end

desc "Build the app then run it in the emulator"
task :emulator => ['emulator:build', 'emulator:install', 'emulator:start']

desc "Build the app then run it in the device"
task :device do
  ['build', 'device:install', 'device:start'].each { |x| Rake::Task[x].invoke }
end

desc "Same as 'rake emulator'"
task :default => :emulator

desc "Same as 'spec:emulator'"
task :spec => 'spec:emulator'

namespace 'spec' do
  desc "Run the test/spec suite on the device"
  task :device do
    App.config.spec_mode = true
    Rake::Task["device"].invoke
  end

  desc "Run the test/spec suite on the emulator"
  task :emulator do
    App.config.spec_mode = true
    Rake::Task["emulator"].invoke
  end
end
