#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

if ARGV.count != 1
  puts "Specify precisely one filename"
else
  files = []
  File.open(ARGV[0]) do |infile|
    while (line = infile.gets)
      parts = line.split(/\t/,2)
      files <<= parts[0]
    end
  end

  counter = 0
  files.each do |file|
    data = File.open(file) {|f| f.read}
    mail = Mail.new(data)
    add = ""
    if tmp=mail.header["X-Uniform-Type-Identifier"] and tmp.value == "com.apple.mail-draft"
      add += "<#DRAFT#> "
    end
    puts "#{file}\t#{mail.from}\t#{add}#{mail.subject}"
    if (counter=counter+1) % 100 == 0
      $stderr.puts "#{counter} / #{files.count}"
    end
  end
end
