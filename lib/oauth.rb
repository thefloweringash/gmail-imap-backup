require 'oauth'
require 'cgi'
require 'net/imap'

module GmailBackup
  module OAuth
    APP_KEY = "anonymous"
    APP_SECRET = "anonymous"

    def self.consumer
      ::OAuth::Consumer.new(APP_KEY, APP_SECRET, {
                              :site               => "https://www.google.com",
                              :request_token_path => "/accounts/OAuthGetRequestToken",
                              :access_token_path  => "/accounts/OAuthGetAccessToken",
                              :authorize_path     => "/accounts/OAuthAuthorizeToken",
                            })
    end

    class XoauthRequest
      attr_reader :method, :uri

      def initialize(method, uri)
        @method = method.upcase
        @uri = uri
      end

      def xoauth(consumer, token)
        helper = ::OAuth::Client::Helper.new(self, {
                                               :consumer => consumer,
                                               :token => token,
                                             })
        oauth_parameters = helper.oauth_parameters
        oauth_parameters['oauth_signature'] = helper.signature(:parameters => oauth_parameters)
        formatted_parameters = oauth_parameters.map { |(k,v)| "#{k}=\"#{CGI.escape(v)}\"" }.sort.join(",")
        "#{@method} #{@uri} #{formatted_parameters}"
      end

      def method
        @method
      end
    end

    class XoauthRequestProxy < ::OAuth::RequestProxy::Base
      proxies XoauthRequest

      def parameters
        options[:parameters]
      end

      def method
        @request.method
      end

      def uri
        @request.uri
      end
    end

    class IMAPAuthenticator
      attr_reader :email, :consumer, :access_token

      def initialize(email, consumer, access_token)
        @email = email
        @consumer = consumer
        @access_token = access_token
      end

      def process(request)
        XoauthRequest.new('GET', "https://mail.google.com/mail/b/#{email}/imap/").
          xoauth(consumer, access_token)
      end
    end
    Net::IMAP.add_authenticator('XOAUTH', IMAPAuthenticator)

  end
end
