#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

config_files = files = Dir.glob("config-*.yml")

config_files.each do |config_file_name|

  config_file = GmailBackup::YAMLFile.new(config_file_name)
  config = config_file.read

  destination_root = config['destination_root']
  raise "No destination" unless destination_root

  statepath = File.join(destination_root, 'state.')
  Lockfile.new statepath+'lock', :retries => 2 do
    GmailBackup::IMAPBackup.new(config).run
  end

end