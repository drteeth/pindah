require "rake"
require "fileutils"
require "tempfile"
require "pp"
require "erb"
require "pathname"

begin
  require 'ant'
rescue LoadError
  abort 'This Rakefile requires JRuby. Please use jruby -S rake.'
end

require "mirah"

module Pindah
  class << self
    include Rake::DSL
  end

  VERSION = '0.1.2'

  def self.infer_sdk_location(path)
    tools = path.split(File::PATH_SEPARATOR).detect {|p| File.exists?("#{p}/android") || File.exists?("#{p}/android.bat") }
    abort "\"android\" executable not found on $PATH" if tools.nil?
    real_location = Pathname.new("#{tools}/android").realpath.dirname
    File.expand_path("#{real_location}/..")
  end

  DEFAULTS = { :output => File.expand_path("bin"),
    :src => File.expand_path("src"),
    :classpath => Dir["jars/*jar", "libs/*jar"],
    :sdk => Pindah.infer_sdk_location(ENV["PATH"])
  }

  TARGETS = { "1.5" => 3, "1.6" => 4,
    "2.1" => 7, "2.2" => 8,
    "2.3" => 9, "2.3.1" => 9, "2.3.2" => 9,
    "2.3.3" => 10, "2.3.4" => 10,
    "3.0" => 11, "3.1" => 12, "3.2" => 13,
    "4.0" => 14, "4.0.3" => 15
  }

  ANT_TASKS = ["clean", "javac", "compile", "debug", "release",
               "release_unsigned", "install", "uninstall"]
  SIGNED_TASKS = ["release"]
  ANT_TASK_MAP = (Hash.new {|h,k| h[k] = k}).merge({ "release_unsigned" => "release" })

  task :generate_manifest # TODO: generate from yaml?

  desc "Tail logs from a device or a device or emulator"
  task :logcat do
    system "adb logcat #{@spec[:log_spec]}"
  end

  desc "Print the project spec"
  task :spec do
    pp @spec
  end

  task :default => [:install]

  def self.spec=(spec)
    abort "Must provide :target_version in Pindah.spec!" if !spec[:target_version]
    abort "Must provide :name in Pindah.spec!" if !spec[:name]

    @spec = DEFAULTS.merge(spec)

    @spec[:root] = File.expand_path "."
    @spec[:target] ||= TARGETS[@spec[:target_version].to_s.sub(/android-/, '')]
    @spec[:classes] ||= "#{@spec[:output]}/classes/"
    @spec[:classpath] << @spec[:classes]

    if @spec.has_key?(:libraries)
      @spec[:libraries].each do |path|
        # TODO: do libraries always build to bin/classes?
        @spec[:classpath] << "#{File.expand_path path}/bin/classes/"
      end
    end

    @spec[:classpath] << "#{@spec[:sdk]}/platforms/android-#{@spec[:target]}/android.jar"
    @spec[:log_spec] ||= "ActivityManager:I #{@spec[:name]}:D " +
      "AndroidRuntime:E *:S"

    ant_setup
  end

  def self.ant_setup
    @ant = Ant.new

    # TODO: this is lame, but ant interpolation doesn't work for project name
    build_template = ERB.new(File.read(File.join(File.dirname(__FILE__), '..',
                                                 'templates', 'build.xml')))
    @build = Tempfile.new(["pindah-build", ".xml"])
    @build.write(build_template.result(binding))
    @build.close

    user_properties = {
      "target" => "android-#{@spec[:target]}",
      "target-version" => "android-#{@spec[:target_version]}",
      "src" => @spec[:src],
      "sdk.dir" => @spec[:sdk],
      "classes" => @spec[:classes],
      "classpath" => @spec[:classpath].join(Java::JavaLang::System::
                                            getProperty("path.separator"))
    }

    if @spec.has_key?(:libraries)
      @spec[:libraries].each_with_index do |path, i|
        prop = "android.library.reference.#{i + 1}"
        # NB: absolute paths do not work
        user_properties[prop] = path
      end
    end

    user_properties.each do |key, value|
      @ant.project.set_user_property(key, value)
    end

    Ant::ProjectHelper.configure_project(@ant.project, java.io.File.new(@build.path))

    # Turn ant tasks into rake tasks
    ANT_TASKS.each do |name, description|
      ant_name = ANT_TASK_MAP[name]

      desc @ant.project.targets[ant_name].description
      task(name) do
        add_signature_properties if SIGNED_TASKS.include?(name)
        @ant.project.execute_target(ant_name)
      end
    end
  end

  protected

  def self.add_signature_properties
    # Add key signing config
    if @spec[:key_store] && @spec[:key_alias]

      # NB: due to a JRuby/Ant bug, Ant can't read these passwords from the
      # command line.
      #
      # So, we'll work around this for now. Icky.
      #
      # See: http://jira.codehaus.org/browse/JRUBY-4827
      puts "Please enter keystore password (store:#{@spec[:key_store]}):"
      store_pw = STDIN.gets.chomp

      puts "Please enter password for alias '#{@spec[:key_alias]}':"
      alias_pw = STDIN.gets.chomp

      signature_properties = {
        "key.store" => @spec[:key_store],
        "key.alias" => @spec[:key_alias],
        "key.store.password" => store_pw,
        "key.alias.password" => alias_pw
      }

      signature_properties.each do |key, value|
        @ant.project.set_user_property(key, value)
      end

      # NB: we need to do this again to actually set the new properties.
      Ant::ProjectHelper.configure_project(@ant.project, java.io.File.new(@build.path))
    end
  end
end
