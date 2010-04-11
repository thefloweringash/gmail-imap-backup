#!/usr/bin/env ruby

# typo protection
UIDVALIDITY='UIDVALIDITY'
UIDNEXT='UIDNEXT'

DEBUG=false

require 'time'
require 'lockfile'
require 'timeout'
require 'net/imap'
require 'yaml'
require 'maildir'

load File.join(File.dirname(__FILE__), 'lib', 'oauth.rb')

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

# config

module GmailBackup
  class IMAPBackup
    attr_reader :imap
    attr_reader :state_file, :local_uidvalidity, :local_uidnext
    attr_reader :mailbox, :email, :destination_root

    def initialize(config_file, state_file)
      @state_file = state_file

      config = config_file.read

      @email = config['email']
      @consumer = GmailBackup::OAuth.consumer
      @access_token = ::OAuth::AccessToken.new(@consumer,
                                               config['access_token'],
                                               config['access_token_secret'])
      @mailbox = config['mailbox']
      @destination_root = config['destination_root']
      raise "No destination" unless @destination_root

      if state_file.exists
        state = state_file.read
        @local_uidvalidity = state[UIDVALIDITY].to_i
        @local_uidnext = state[UIDNEXT].to_i
      else
        @local_uidvalidity = nil
        @local_uidnext = nil
      end

      if local_uidvalidity and !local_uidnext
        raise "Corrupted state, local_uidnext is missing"
      end
    end

    def run
      @imap = Net::IMAP.new("imap.gmail.com", 993, true, "/etc/ssl/certs", true)
      begin
        puts "Connected" if DEBUG

        imap.authenticate('XOAUTH', email, consumer, access_token)

        puts "Authenticated" if DEBUG

        imap.examine(mailbox)

        remote_uidvalidity = imap.responses[UIDVALIDITY][-1].to_i
        remote_uidnext     = imap.responses[UIDNEXT][-1].to_i

        if DEBUG
          puts "remote_uidvalidity = #{remote_uidvalidity}"
          puts "remote_uidnext = #{remote_uidnext}"
          puts "local_uidvalidity = #{local_uidvalidity}"
          puts "local_uidnext = #{local_uidnext}"
        end

        uids = if local_uidvalidity != remote_uidvalidity
                 puts "UIDVALIDITY mismatch, starting over" if DEBUG
                 imap.fetch(1 .. -1, "UID")
               elsif local_uidnext != remote_uidnext
                 puts "Incremental update (#{local_uidnext}..#{remote_uidnext}" if DEBUG
                 imap.uid_fetch(local_uidnext .. -1, "UID")
               else
                 puts "No work" if DEBUG
                 []
               end.map { |x| x.attr['UID'].to_i }

        puts "Want to fetch: #{uids.inspect}" if DEBUG

        uids.each { |x| fetch_and_store_message(x) }

        state_file.write({
                           UIDVALIDITY => remote_uidvalidity,
                           UIDNEXT     => remote_uidnext
                         })

      rescue => e
        puts e.inspect
        puts e.backtrace

        puts "Error occured, logging out"
        Timeout::timeout(10) do
          imap.logout
        end
      end
    end

    private

    def fetch_and_store_message(uid)
      imap.uid_fetch(uid, ['RFC822', 'INTERNALDATE']).each do |message|
        dir = Maildir.new(File.join(destination_root, ".#{Date.today.to_s}"))
        internaldate = Time.parse(message.attr['INTERNALDATE'])
        file = dir.add(message.attr['RFC822']).path
        File.utime(File.atime(file), internaldate, file)
      end
    end

    attr_reader :access_token, :consumer

  end
end

Lockfile.new 'state.lock', :retries => 2 do
  config_file = YAMLFile.new('config')
  state_file = YAMLFile.new('state')

  GmailBackup::IMAPBackup.new(config_file, state_file).run
end
