require 'yaml'

module GmailBackup
  class YAMLFile
    attr_reader :filename

    def initialize(filename)
      @filename = filename
    end

    def read
      File.open(filename) { |f| YAML.load(f) }
    end

    def write(o)
      str = o.to_yaml
      File.open(filename, "w") { |f| f.puts str }
    end

    def exists
      File.exists? filename
    end
  end
end
