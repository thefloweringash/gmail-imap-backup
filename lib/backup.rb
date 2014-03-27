#!/usr/bin/env ruby

require 'time'
require 'lockfile'
require 'timeout'
require 'net/imap'
require 'maildir'
require 'mail'

require File.join(File.dirname(__FILE__), 'oauth.rb')
require File.join(File.dirname(__FILE__), 'yamlfile.rb')
require File.join(File.dirname(__FILE__), 'emailhash.rb')
require 'gmail_xoauth'

require 'google/api_client'

module GmailBackup
  # typo protection
  UIDVALIDITY='UIDVALIDITY'
  UIDNEXT='UIDNEXT'
  UIDS='UIDS'
  EXISTS='EXISTS'

  DEBUG=false

  class IMAPBackup
    attr_reader :imap
    attr_reader :mailbox, :email, :destination_root, :mailboxpath
    attr_reader :imap_server, :password
    

    def initialize(config)
      STDOUT.sync = true
      
      @all_successfull = true
      
      @email = config['email']
      @consumer = GmailBackup::OAuth.consumer

      if config['access_token'] == ''
        puts @consumer.to_yaml
      if config['service_account_clientid']
        client = Google::APIClient.new(
          :application_name => 'Hajo EMail Backup',
          :application_version => '1.0.0'
        )

        key = Google::APIClient::KeyUtils.load_from_pkcs12(config['service_account_key_file'], config['service_account_key_pass'])
        client.authorization = Signet::OAuth2::Client.new(
          :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
          :audience => 'https://accounts.google.com/o/oauth2/token',
          :scope => 'https://mail.google.com/',
          :issuer => config['service_account_clientid'],
          :person => email,
          :signing_key => key)
        client.authorization.fetch_access_token!
        @access_token_v2 = client.authorization.access_token
      end

        @request_token=@consumer.get_request_token( { :oauth_callback => "oob" }, {:scope => config['oauthscope'] || "https://mail.google.com/"} )
        puts "Please go to: " + @request_token.authorize_url

        puts "Please enter the verification code provided:"
        oauth_verifier = STDIN.gets.chomp

        @access_token=@request_token.get_access_token(:oauth_verifier => oauth_verifier)
        puts "Add this to your config.yml:" + {'access_token'=>@access_token.token, 'access_token_secret'=>@access_token.secret}.to_yaml

        exit
      end
      if config['access_token']
        @access_token = ::OAuth::AccessToken.new(@consumer, config['access_token'], config['access_token_secret'])
      end
      
      @mailbox = config['mailbox']
      @destination_root = config['destination_root']
      raise "No destination" unless @destination_root
      
      @imap_server = config['imapserver'] 
      @password = config['password']

    end

    def connect
      @imap = Net::IMAP.new(imap_server ||"imap.gmail.com", 993, true, "/etc/ssl/certs/cacert.pem", true)
      puts "Connected" if DEBUG
    end

    def authenticate
      if access_token_v2 
        imap.authenticate('XOAUTH2', email, access_token_v2)
      elsif access_token 
          imap.authenticate('XOAUTH', email, consumer, access_token)
      else
        imap.login(email, password)
      end
      puts "Authenticated" if DEBUG
    end

    def cleanup
      begin
        if imap
          puts "Logging out" if DEBUG
          Timeout::timeout(10) do
            imap.logout
          end
        end
      rescue Exception
      end
    end

    def run
      begin
        connect
        authenticate
        
        mailboxes = imap.list(mailbox, "*")
        if mailboxes
          mailboxes = mailboxes.collect{|m| m.name} 
        else
          mailboxes = [mailbox]
        end
        puts "\nMailboxes for #{email}: #{mailboxes.to_yaml}\n"

        mailboxes.each do |curmailbox|
          puts "\n#{email}    === #{curmailbox} ==="
          
          @mailboxpath = File.join(destination_root, curmailbox)
          Dir.mkdir(mailboxpath) unless File.directory?(mailboxpath)
          statepath = File.join(mailboxpath, 'state.')
          
          state_file = GmailBackup::YAMLFile.new(statepath+'yml')
          todo_file = GmailBackup::YAMLFile.new(statepath+'todo.yml')
          
          if state_file.exists
            state = state_file.read
            local_uidvalidity = state[UIDVALIDITY].to_i
            local_uidnext = state[UIDNEXT].to_i
          else
            local_uidvalidity = nil
            local_uidnext = nil
          end

          if local_uidvalidity and !local_uidnext
            raise "Corrupted state.yml, local_uidnext is missing"
          end

          if todo_file.exists
            todo = todo_file.read
            todo_uids = todo[UIDS]
          else
            todo_uids = []
          end
          raise "state.todo.yml corrupted" unless todo_uids

          
          imap.examine(curmailbox)
          numberofemail = imap.responses[EXISTS][-1].to_i
          puts "Number of EMails: #{numberofemail}"
          next unless numberofemail > 0

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
          abortloop = false

          begin
            uids.each do |x| 
              Timeout::timeout(300) do
                fetch_and_store_message(x)
                uidsleft.delete(x)
              end
            
              writefile = writefile - 1
              if writefile < 0
                 writefile = 1000
                 
                 print "(#{uidsleft.count})"
               
                 # Every 1000 items, update todo file
                 todo_file.write({ UIDS => uidsleft })
                 puts "Wrote status.todo.yml" if DEBUG
              end
            end
          rescue   Exception
            puts $!, *$@
            puts "Apparently something went wrong or we took more than 300 seconds for one single message ..."
            abortloop = true
            @all_successfull = false
          end

          # This sometimes crashes, but in that case we'll just use the older todo file...
          state_file.write({ UIDVALIDITY => remote_uidvalidity, UIDNEXT => remote_uidnext })
          todo_file.write({ UIDS => uidsleft })
          puts "Wrote new status.yml and status.todo.yml" if DEBUG
        
          break if abortloop
          
        end
        
      ensure
        cleanup
      end
      
      if @all_successfull 
        successpath = File.join(destination_root, 'success.txt')
        File.open(successpath, 'w') {|f| f.write(DateTime.now.to_s) }
        
      end
    end


    def get_hashes
      begin
        connect
        authenticate
        
        Net::IMAP.debug= false
        mailboxes = imap.list(mailbox, "*")
        if mailboxes
          mailboxes = mailboxes.collect{|m| m.name} 
        else
          mailboxes = [mailbox]
        end
        
        mailboxes.each do |curmailbox|
          $stderr.puts "curmailbox: #{curmailbox}"
          imap.examine(curmailbox)
          numberofemail = imap.responses[EXISTS][-1].to_i
          next unless numberofemail > 0

          messages = imap.fetch(1 .. -1, "(BODY.PEEK[HEADER.FIELDS (Date From Message-ID)])")
          next unless messages
          
          messages.each do |x| 
            hash = EmailHash.hashme(x.attr["BODY[HEADER.FIELDS (Date From Message-ID)]"]) 
            puts "MAILBOX\t#{hash}"
          end
        end
      ensure
        cleanup
      end
    end



    def upload_messages(target_mailbox, paths, outfile)
      done = []
      begin
        connect
        authenticate
        
        Net::IMAP.debug= false
        mailboxes = imap.list(mailbox, "*")
        if mailboxes
          mailboxes = mailboxes.collect{|m| m.name} 
        else
          mailboxes = [mailbox]
        end
        
        mailboxes.each do |curmailbox|
          puts "curmailbox: #{curmailbox}"
          next unless curmailbox == target_mailbox
          puts "Found target Mailbox :)"

          paths.each do |file|
            data = File.open(file) {|f| f.read}
            mail = Mail.new(data)
            puts "uploading #{file} size #{data.length} date #{mail.date}"
            if mail.date
              maildate = Time.mktime(mail.date.year, mail.date.month, mail.date.day, mail.date.hour, mail.date.min, mail.date.sec, mail.date.zone)
            else
              maildate = Time.now
            end

            done <<= file
            begin
              imap.append(curmailbox, data, [:Seen], maildate )
            rescue   Exception
              puts $!, *$@
              outfile.puts "#{file}\t#{mail.from} #{mail.subject}"
              outfile.flush
              break
            end
          end
        end        
      rescue   Exception
        puts $!, *$@
      ensure
        cleanup
      end
      return done
    end


    private

    def fetch_and_store_message(uid)
      puts "Fetch and store: #{uid}" if DEBUG
      print "." if not DEBUG
      
      messages = imap.uid_fetch(uid, ['RFC822', 'INTERNALDATE'])
      return unless messages
      
      messages.each do |message|
        dir = Maildir.new(File.join(mailboxpath, ".#{Date.today.to_s}"))
        internaldate = Time.parse(message.attr['INTERNALDATE'])
        file = dir.add(message.attr['RFC822']).path
        File.utime(File.atime(file), internaldate, file)
      end
    end

    attr_reader :access_token, :consumer
    attr_reader :access_token_v2

  end
end
