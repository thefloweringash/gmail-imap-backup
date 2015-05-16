#!/usr/bin/env ruby

require 'time'
require 'lockfile'
require 'timeout'
require 'net/imap'
require 'maildir'
require 'signet/oauth_2/client'
require 'gmail_xoauth'

require File.join(File.dirname(__FILE__), 'yamlfile.rb')

module GmailBackup
  # typo protection
  UIDVALIDITY='UIDVALIDITY'
  UIDNEXT='UIDNEXT'

  DEBUG=false

  class IMAPBackup
    attr_reader :imap
    attr_reader :state_file, :local_uidvalidity, :local_uidnext
    attr_reader :mailbox, :email, :destination_root

    def initialize(config_file, state_file)
      @state_file = state_file

      config = config_file.read

      @email = config['email']
      @client_id = config['client_id']
      @client_secret = config['client_secret']
      @refresh_token = config['refresh_token']
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

    def new_access_token!
      Signet::OAuth2::Client.new(
        :token_credential_uri => "https://www.googleapis.com/oauth2/v3/token",
        :client_id => @client_id,
        :client_secret => @client_secret,
        :refresh_token => @refresh_token,
      ).fetch_access_token["access_token"]
    end

    def connect
      @imap = Net::IMAP.new("imap.gmail.com", 993, true, "/etc/ssl/certs", true)
      puts "Connected" if DEBUG
    end

    def authenticate(access_token)
      imap.authenticate('XOAUTH2', email, access_token)
      puts "Authenticated" if DEBUG
    end

    def cleanup
      if imap
        puts "Logging out" if DEBUG
        Timeout::timeout(10) do
          imap.logout
        end
      end
    end

    def run
      begin
        access_token = new_access_token!
        connect
        authenticate(access_token)

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
                 puts "Incremental update (#{local_uidnext}:*)" if DEBUG
                 imap.uid_fetch(local_uidnext .. -1, "UID").
                   select { |x| x.attr['UID'].to_i >= local_uidnext }
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
      ensure
        cleanup
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
  end
end
