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
      File.open(filename, "w") { |f| f.puts o.to_yaml }
    end

    def exists
      File.exists? filename
    end
  end
end
