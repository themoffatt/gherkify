require 'gherkify/version'
require 'gherkify/feature'

require 'gherkin/parser/parser'
require 'gherkin/formatter/json_formatter'
require 'stringio'
require 'json'


class Gherkify

  def initialize(files, options={})
    @files = files

    @options = {
      show_notes: false,
      output_dir: '.',
      debug: false,
      add_features: false
    }.merge options
  end

  # Parses feature files
  #
  # @param files [Array] the array of feature files to be parsed
  # @return [Array] the array of parsed features
  def self.parse_files(files, options={})
    Gherkify.new(files, options)
  end

  # Parses feature file
  #
  # @param file [String] the path to feature file to be parsed
  # @return [Array] the array of parsed features
  def self.parse_file(file)
    self.parse_files([file])
  end

  def features
    @features ||= parse
  end

  def parse
    parse_files
  end

  def parse_files(files=nil)
    @files = files if !files.nil?
    files = @files if files.nil?

    io = StringIO.new
    formatter = Gherkin::Formatter::JSONFormatter.new(io)
    parser = Gherkin::Parser::Parser.new(formatter)

    files.each do |path|
      parser.parse(IO.read(path), path, 0)
    end

    formatter.done
    # ap JSON.parse(io.string, :symbolize_names => true)
    features_data = JSON.parse(io.string, :symbolize_names => true)
    @features = features_data.collect { |e| Gherkify::Feature.new(e)  }
  end

  def check_and_fetch_diagram(diagram, pngs, output_dir)
    unless pngs.include? "#{diagram.md5}.png"
      puts "Fetching yuml to #{output_dir}/#{diagram.md5}.png"
      diagram.to_png("#{output_dir}/#{diagram.md5}.png")
    end
  end

  def fetch_diagram_images
    output_dir = @options[:image_path]

    pngs = []
    Dir.chdir(output_dir) do
      pngs = Dir.glob("*.png")
    end

    features.each do |feature|
      use_case = feature.yuml.use_case
      check_and_fetch_diagram(use_case, pngs, output_dir)
      
      feature.scenarios.each do |e|
        activity = feature.yuml.activity(e)
        check_and_fetch_diagram(activity, pngs, output_dir)
      end
    end

    check_and_fetch_diagram(yuml_ui_elements, pngs, output_dir) if yuml_ui_elements

  end

  def ui_elements_merge!(all, current)
    #@ui_screens[screen_name] = { buttons: [], connections: [] } if @ui_screens[screen_name].nil?
    current.each do |screen_name, data|
      if all[screen_name].nil?
        all[screen_name] = data
        next
      else
        all[screen_name].each do |k, v|
          all[screen_name][k] += data[k] if !data[k].nil?
          all[screen_name][k].uniq!
        end
      end
    end
  end

  def collect_ui_elements
    all_elements = {}
    features.each do |feature|
      elements = feature.ui_elements
      ui_elements_merge!(all_elements, elements)
    end
    all_elements
  end

  def yuml_ui_elements
    @yuml_ui_elements ||= Gherkify::FeatureYuml.ui_elements(collect_ui_elements)
  end

  def to_s
    s = []
    features.each { |e| s << e.to_s }
    s << "UI elements:" << yuml_ui_elements.to_s if yuml_ui_elements
    s * "\n"
  end

  def img_path(image_name)
    File.join(@options[:image_path], "#{image_name}.png")
  end

  def to_md(file=nil)

    # fetch_diagram_images

    output_dir = @options[:output_dir]

    s = []
    s << "## Features"
    features.each do |feature|
      s << "### #{feature.name}"

      use_case = feature.yuml.use_case
      # s << "*TODO: Fetch and store use_case by MD5: #{use_case.md5}*"
      # s << "```\n#{use_case.to_s}```"
      s << "![#{feature.name}](#{img_path(use_case.md5)})"
      s << ''

      feature.scenarios.each do |e|
        name = feature.scenario_name(e)
        activity = feature.yuml.activity(e)
        s << "- **#{name}**"
        # s << "*TODO: Fetch and store activity by MD5: #{activity.md5}*"
        # s << "```\n#{activity.to_s}```"
        s << "![#{name}](#{img_path(activity.md5)})"
        s << ''
      end
    end

    if yuml_ui_elements
      s << "## UI Elements"
      s << "*Screens and actions*"
      s << "![UI Screens and actions](#{img_path(yuml_ui_elements.md5)})"
      # s << yuml_ui_elements.to_s
      s << ''
    end

    if @options[:add_features]
      s << ''
      s << "## Use cases listing"
      @files.each do |f_file| 
        f = File.open(f_file, "rb")
        contents = f.read
        s << ''
        s << '``` gherkin'
        s << contents
        s << '```'
        s << ''
      end
    end

    s = s * "\n"
    return s if file.nil?

    writer = open(File.join(output_dir, file), "wb")
    writer.write(s)
    writer.close

  end

end
