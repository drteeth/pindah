require 'fileutils'
require 'erb'

module PindahCLI
  DEFAULT_TARGET_VERSION = '4.0.3'

  def self.create(package, location=nil, activity_name='HomeActivity')
    segments = package.split('.')
    location ||= segments.last
    src_dir  = File.join(location, 'src', *segments)

    mkdir location, File.join('src', *segments)
    mkdir location, 'bin'
    mkdir location, 'libs'
    mkdir location, 'res'
    mkdir location, 'res/drawable-hdpi'
    mkdir location, 'res/drawable-ldpi'
    mkdir location, 'res/drawable-mdpi'
    mkdir location, 'res/layout'
    mkdir location, 'res/values'

    name = File.basename(location)
    app_name = name.split(/[-_]/).map{ |w| w.capitalize }.join(" ")

    FileUtils.mkdir_p src_dir

    create_templated("Rakefile", location, binding)
    create_templated("AndroidManifest.xml", location, binding)
    create_templated("main.xml", File.join(location, 'res', 'layout'), binding)
    create_templated("strings.xml", File.join(location, 'res', 'values'), binding)
    create_templated(".gitignore", location, binding)

    # Default icons of various sizes
    ["hdpi", "mdpi", "ldpi"].each do |s|
      FileUtils.cp(File.join(File.dirname(__FILE__), '..', 'templates', "res",
                             "drawable-#{s}", "ic_launcher.png"),
                   File.join(location, "res", "drawable-#{s}", "ic_launcher.png"))
    end

    log "Created project in #{location}."

    if activity_name
      activity_location = File.join(src_dir, "#{activity_name}.mirah")
      activity_template = File.read(File.join(File.dirname(__FILE__),
                                              '..', 'templates',
                                              'initial_activity.mirah'))

      File.open(activity_location, 'w') do |f|
        template_with_classname = activity_template.gsub(/INITIAL_ACTIVITY/, activity_name)
        f.puts ERB.new(template_with_classname).result(binding)
      end
      log "Created Activity '#{activity_name}' in '#{activity_location}'."
      log "cp $ANDROID_SDK_ROOT/extras/android/support/v4/android-support-v4.jar ./#{location}/libs/"
    end
  end

  private

  def self.log(msg)
    STDERR.puts msg
  end

  def self.create_templated(name, project_location, scope)
    location = File.join(project_location, name)
    template = File.read(File.join(File.dirname(__FILE__),
                                   '..', 'templates', name))

    File.open(location, 'w') do |f|
      f.puts ERB.new(template).result(scope)
    end
  end

  def self.mkdir(base, directory)
    location = File.join(base, directory)
    FileUtils.mkdir_p location
    log "Created '#{location}'."
  end
end
