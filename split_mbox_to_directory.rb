#!/usr/bin/env ruby

require 'rubygems'
require 'mail'
require 'maildir'

from = ARGV[0]
targetpath = ARGV[1]

Dir.mkdir(targetpath) unless File.directory?(targetpath)
maildir = Maildir.new(targetpath)

def starts_with?(str, prefix)
  prefix = prefix.to_s
  str[0, prefix.length] == prefix
end

def write_mail(maildir, mail,counter)
#  puts "PARSE MAIL: ### #{mail} ###"
parseme = mail[0, [mail.length, 10000].min ]
  parsedmail = Mail.new(parseme)
  from = parsedmail.from || "NOFROM"
  subject = parsedmail.subject || "NOSUBJECT"
  
  puts "WRITE MAIL: #{from}   #{subject} "
  maildir.add(mail)
end

linesInThisEmail = 0
counter = 0
currentEmail = ""
lastLineWasEmpty = true
File.open(from,  'r+:ASCII-8BIT') do |file|
  while (line = file.gets)
#    puts "line: '#{line}'" 
#    puts "starts: #{starts_with?(line.downcase, "from")} lastE: #{lastLineWasEmpty}" 
    if starts_with?(line.downcase, "from") && lastLineWasEmpty 
      # starting a new mail
      write_mail(maildir, currentEmail,counter)
      counter = counter + 1
      linesInThisEmail = 0
      currentEmail = ""
    end
    lastLineWasEmpty = line.length < 3
    currentEmail << line
     linesInThisEmail =  linesInThisEmail + 1
     if linesInThisEmail % 1000 == 0
       puts "linesInThisEmail: #{linesInThisEmail}"
     end
  end
end
write_mail(maildir, currentEmail,counter)
