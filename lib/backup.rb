#!/usr/bin/env ruby

require 'time'
require 'lockfile'
require 'timeout'
require 'net/imap'
require 'maildir'

require File.join(File.dirname(__FILE__), 'oauth.rb')
require File.join(File.dirname(__FILE__), 'yamlfile.rb')

module GmailBackup
  # typo protection
  UIDVALIDITY='UIDVALIDITY'
  UIDNEXT='UIDNEXT'
  UIDS='UIDS'

  DEBUG=true

  class IMAPBackup
    attr_reader :imap
    attr_reader :state_file, :local_uidvalidity, :local_uidnext
    attr_reader :mailbox, :email, :destination_root

    attr_reader :todo_file, :todo_uids

    def initialize(config, state_file, todo_file)
      @state_file = state_file
      @todo_file = todo_file

      @email = config['email']
      @consumer = GmailBackup::OAuth.consumer

      if config['access_token'] == ''
        puts @consumer.to_yaml

        @request_token=@consumer.get_request_token( { :oauth_callback => "oob" }, {:scope => "https://mail.google.com/"} )
        puts "Please go to: " + @request_token.authorize_url

        puts "Please enter the verification code provided:"
        oauth_verifier = STDIN.gets.chomp

        @access_token=@request_token.get_access_token(:oauth_verifier => oauth_verifier)
        puts "Add this to your config.yml:" + {'access_token'=>@access_token.token, 'access_token_secret'=>@access_token.secret}.to_yaml

        exit
      end
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
        raise "Corrupted state.yml, local_uidnext is missing"
      end

      if todo_file.exists
        todo = todo_file.read
        @todo_uids = todo[UIDS]
      else
        @todo_uids = []
      end
      raise "state.todo.yml corrupted" unless @todo_uids

    end

    def connect
      @imap = Net::IMAP.new("imap.gmail.com", 993, true, "/etc/ssl/certs", true)
      puts "Connected" if DEBUG
    end

    def authenticate
      imap.authenticate('XOAUTH', email, consumer, access_token)
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
        connect
        authenticate

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
          todo_uids.clear
          imap.fetch(1 .. -1, "UID")
        elsif local_uidnext != remote_uidnext
          puts "Incremental update (#{local_uidnext}:*)" if DEBUG
          imap.uid_fetch(local_uidnext .. -1, "UID").
          select { |x| x.attr['UID'].to_i >= local_uidnext }
        else
          puts "No new messages on server" if DEBUG
          []
        end.map { |x| x.attr['UID'].to_i }

        puts "Want to fetch: #{uids.inspect}" if DEBUG
        puts "Old UIDs to fetch: #{todo_uids.inspect}" if DEBUG
        uids = uids + todo_uids;

        uidsleft = Array.new(uids)

        # Write current status before we start processing
        state_file.write({ UIDVALIDITY => remote_uidvalidity, UIDNEXT => remote_uidnext })
        todo_file.write({ UIDS => uidsleft })
 
        writefile = -1

        begin
          uids.each do |x| 
            Timeout::timeout(300) do
              fetch_and_store_message(x)
              uidsleft.delete(x)
            end
            
            writefile = writefile - 1
            if writefile < 0
               writefile = 100
               
               # Every 100 items, update todo file
               todo_file.write({ UIDS => uidsleft })
               puts "Wrote status.todo.yml" if DEBUG
            end
          end
        rescue   Exception
          puts $!, *$@
          puts "Apparently something went wrong or we took more than 300 seconds for one single message ..."
        end

        # This sometimes crashes, but in that case we'll just use the older todo file...
        state_file.write({ UIDVALIDITY => remote_uidvalidity, UIDNEXT => remote_uidnext })
        todo_file.write({ UIDS => uidsleft })
        puts "Wrote new status.yml and status.todo.yml" if DEBUG
      ensure
        cleanup
      end
    end

    private

    def fetch_and_store_message(uid)
      puts "Fetch and store: #{uid}" if DEBUG
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
