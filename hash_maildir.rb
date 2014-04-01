#!/usr/bin/env ruby

require 'rubygems'
require 'maildir'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

def hash_dir(path)
  maildir = Maildir.new(path, false)

  [:cur, :new, :tmp].each do |mailstat|
    $stderr.puts "#{maildir.path}: #{mailstat}"
    counter = 0
    files = maildir.list(mailstat)
    files.each do |file|
      parseme = file.data
      parseme = parseme[0, [parseme.length, 10000].min ]
      hash = EmailHash.hashme(parseme) 
      puts "#{file.path}\t#{hash}"
      if (counter=counter+1) % 100 == 0
        $stderr.puts "#{counter} / #{files.count}"
      end
    end
  end

  Dir.open(path) do |dir|
    dir.each do |key|
      #$stderr.puts "key: #{key}"
      next if key == '.' or key == '..'

      dirpath = File.join(path, key)
      next unless File.directory? dirpath

      hash_dir(dirpath)
    end
  end
end

ARGV.each do |maildir_path|
  hash_dir(maildir_path)
end