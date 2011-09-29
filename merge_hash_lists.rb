#!/usr/bin/env ruby

require 'rubygems'
require File.join(File.dirname(__FILE__), 'lib', 'backup.rb')

if ARGV.count == 0 or ARGV.count%2 != 0
  puts "Always -a[dd] <file> or -r[em] <file>"
else
  num_files = ARGV.count/2
  hash2path = {}
  (0..num_files-1).each do |fileindex|
    op = ARGV[fileindex*2 + 0]
    file = ARGV[fileindex*2 + 1]
    $stderr.puts "op: #{op} file: #{file}"

    add = (op == '-a' or op == '-add')
    File.open(file) do |infile|
      while (line = infile.gets)
        parts = line.split(/\t/,2)
        if add
          hash2path[parts[1]] = parts[0]
        else
          hash2path.delete(parts[1])
        end 
      end
    end
  end

  hash2path.each do |hash, path|
    puts "#{path}\t#{hash}"
  end
end