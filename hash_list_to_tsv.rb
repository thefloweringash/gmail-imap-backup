#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

if ARGV.count != 1
  puts "Specify precisely one filename"
else
  File.open(ARGV[0]) do |infile|
    while (line = infile.gets)
      parts = line.split(/\t/,2)
      data = File.open(parts[0]) {|f| f.read}
      mail = Mail.new(data)
      add = ""
      if tmp=mail.header["X-Uniform-Type-Identifier"] and tmp.value == "com.apple.mail-draft"
        add += "<#DRAFT#> "
      end
      puts "#{parts[0]}\t#{mail.from}\t#{add}#{mail.subject}"
    end
  end
end
