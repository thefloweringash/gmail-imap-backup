#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

ARGV.each do |config_file_name|

  config_file = GmailBackup::YAMLFile.new(config_file_name)
  config = config_file.read

  GmailBackup::IMAPBackup.new(config).get_hashes
end