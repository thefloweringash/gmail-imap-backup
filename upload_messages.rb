#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

if ARGV.count != 3
  puts "usage: config-file.yml hash-list.txt target_mailbox"
else
  config_file_name = ARGV[0]
  hash_file_name = ARGV[1]
  target_mailbox = ARGV[2]

  paths = []


  File.open(hash_file_name) do |infile|
    while (line = infile.gets)
      parts = line.split(/\t/,2)
      paths <<= parts[0]
    end
  end

  puts "Connecting to upload #{paths.count} messages ..."

  config_file = GmailBackup::YAMLFile.new(config_file_name)
  config = config_file.read

  File.open(hash_file_name + '.failed.txt','a') do |outfile|
    while paths.count > 0
      done = GmailBackup::IMAPBackup.new(config).upload_messages(target_mailbox, paths, outfile)
      paths = paths - done
    end
  end
end
