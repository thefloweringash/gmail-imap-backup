#!/usr/bin/env ruby

require 'rubygems'
require 'maildir'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

def hash_dir(path)
  maildir = Maildir.new(path, false)

  [:cur, :new, :tmp].each do |mailstat|
    files = maildir.list(mailstat)
    files.each do |file|
      parseme = file.data
      parseme = parseme[0, [parseme.length, 10000].min ]
      hash = EmailHash.hashme(parseme) 
      puts "#{file.path}\t#{hash}"
    end
  end

  search_path = File.join(path, '*')
  keys = Dir.glob(search_path, File::FNM_DOTMATCH)
  keys.each do |key|
#    puts "key: #{key}"
    next unless File.directory? key
    next if File.basename(key) == '.'
    next if File.basename(key) == '..'
    hash_dir(key)
  end
end

ARGV.each do |maildir_path|
  hash_dir(maildir_path)
end