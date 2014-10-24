# Copyright 2014 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'addressable/uri'
require 'jwt'
require 'multi_json'
require 'rpc_helper'
require 'uri'

module GitkitLib

  class GitkitClient

    # Create a client from json config file
    #
    # @param [String] file file name of the json-format config
    def self.create_from_config_file(file)
      config = MultiJson.load File.open(file, 'rb') { |io| io.read }
      p12key = File.open(config['serviceAccountPrivateKeyFile'], 'rb') {
          |io| io.read }
      new(
          config['clientId'],
          config['serviceAccountEmail'],
          p12key,
          config['widgetUrl'],
          config['serverApiKey'])
    end

    # Initializes a GitkitClient.
    #
    # @param [String] client_id Google oauth2 web client id of this site
    # @param [String] service_account_email Google service account email
    # @param [String] service_account_key Google service account private p12 key
    # @param [String] widget_url full url to host the Gitkit widget
    # @param [String] server_api_key server-side Google API key
    def initialize(client_id, service_account_email, service_account_key,
        widget_url, server_api_key = nil)
      @client_id = client_id
      @widget_url = widget_url
      @rpc_helper = RpcHelper.new(service_account_email, service_account_key,
          server_api_key)
      @certificates = {}
    end

    # Verifies a Gitkit token
    #
    # @param [String] token_string the token to be verified
    # @return [GitkitUser, nil] for valid token, [nil, String] otherwise with
    # error_message.
    def verify_gitkit_token(token_string)
      if token_string.nil?
        return nil, 'no token'
      end
      begin
        key_finder = lambda {|header|
          key_id = header['kid']
          unless @certificates.has_key? key_id
            @certificates = Hash[get_certs.map {|key,cert|
                [key, OpenSSL::X509::Certificate.new(cert)]}]
          end
          @certificates[key_id].public_key }
        parsed_token, _ = JWT.decode(token_string, nil, true, &key_finder)
        # check expiration time
        if Time.new.to_i > parsed_token['exp']
          return nil, 'token expired'
        end
        # check audience
        if parsed_token['aud'] != @client_id
          return nil, 'audience mismatch'
        end
        GitkitUser.parse_from_api_response parsed_token
      rescue JWT::DecodeError => e
        return nil, e.message
      end
    end

    # Gets Gitkit public certs
    #
    # @api private
    def get_certs
      @rpc_helper.get_gitkit_certs()
    end

    # Gets user info by email
    #
    # @param [String] email user email
    # @return [GitkitUser] for the email
    def get_user_by_email(email)
      response = @rpc_helper.get_user_by_email email
      GitkitUser.parse_from_api_response response.fetch('users', [{}])[0]
    end

    # Gets user info by user id
    #
    # @param [String] id user id
    # @return [GitkitUser] for the id
    def get_user_by_id(id)
      response = @rpc_helper.get_user_by_id id
      GitkitUser.parse_from_api_response response.fetch('users', [{}])[0]
    end

    # Downloads all user accounts from Gitkit service
    #
    # @param [Fixnum] max_results pagination size of each request
    # @yield [GitkitUser] individual user account
    def get_all_users(max_results = 10)
      next_page_token = nil
      while true
        next_page_token, accounts = @rpc_helper.download_account(
            next_page_token, max_results)
        accounts.each { |account|
          yield GitkitUser.parse_from_api_response account }
        if not next_page_token or accounts.length == 0
          break
        end
      end
    end

    # Uploads multiple accounts to Gitkit service
    #
    # @param [String] hash_algorithm password hash algorithm
    # @param [String] hash_key key of the hash algorithm
    # @param [Array<GitkitUser>] accounts user accounts to be uploaded
    def upload_users(hash_algorithm, hash_key, accounts)
      account_request = accounts.collect { |account| account.to_request }
      @rpc_helper.upload_account hash_algorithm, JWT.base64url_encode(hash_key),
          account_request
    end

    # Deletes a user account from Gitkit service
    #
    # @param [String] local_id user id to be deleted
    def delete_user(local_id)
      @rpc_helper.delete_account local_id
    end

    # Get one-time out-of-band code for ResetPassword/ChangeEmail request
    #
    # @param [Hash{String=>String}] param dict of HTTP POST params
    # @param [String] user_ip end user's IP address
    # @param [String] gitkit_token the gitkit token if user logged in
    #
    # @return [Hash] {
    #    email: user email who is asking reset password
    #    oobLink: the generated link to be send to user's email
    #    action: OobAction
    #    response_body: the http body to be returned
    #  }
    def get_oob_result(param, user_ip, gitkit_token=nil)
      if param.has_key? 'action'
        begin
          if param['action'] == 'resetPassword'
            oob_link = build_oob_link(
                password_reset_request(param, user_ip),
                param['action'])
            return password_reset_response(oob_link, param)
          elsif param['action'] == 'changeEmail'
            unless gitkit_token
              return failure_msg('login is required')
            end
            oob_link = build_oob_link(
                change_email_request(param, user_ip, gitkit_token),
                param['action'])
            return email_change_response(oob_link, param)
          end
        rescue GitkitClientError => error
          return failure_msg(error.message)
        end
      end
      failure_msg('unknown request type')
    end

    def password_reset_request(param, user_ip)
      {
        'email' => param['email'],
        'userIp' => user_ip,
        'challenge' => param['challenge'],
        'captchaResp' => param['response'],
        'requestType' => 'PASSWORD_RESET'
      }
    end

    def change_email_request(param, user_ip, gitkit_token)
      {
        'email' => param['oldEmail'],
        'newEmail' => param['newEmail'],
        'userIp' => user_ip,
        'idToken' => gitkit_token,
        'requestType' => 'NEW_EMAIL_ACCEPT'
      }
    end

    def build_oob_link(param, mode)
      code = @rpc_helper.get_oob_code(param)
      if code
        oob_link = Addressable::URI.parse @widget_url
        oob_link.query_values = { 'mode' => mode, 'oobCode' => code}
        return oob_link.to_s
      end
      nil
    end

    def failure_msg(msg)
      {:response_body => MultiJson.dump({'error' => msg})}
    end

    def email_change_response(oob_link, param)
      {
        :oldEmail => param['email'],
        :newEmail => param['newEmail'],
        :oobLink => oob_link,
        :action => :CHANGE_EMAIL,
        :response_body => MultiJson.dump({'success' => true})
      }
    end

    def password_reset_response(oob_link, param)
      {
        :email => param['email'],
        :oobLink => oob_link,
        :action => :RESET_PASSWORD,
        :response_body => MultiJson.dump({'success' => true})
      }
    end
  end

  class GitkitUser
    attr_accessor :email, :user_id, :name, :photo_url, :provider_id,
        :email_verified, :password_hash, :salt, :password, :provider_info

    def self.parse_from_api_response(api_response)
      user = self.new
      user.email = api_response.fetch('email', nil)
      user.user_id = api_response.fetch('user_id',
          api_response.fetch('localId', nil))
      user.name = api_response.fetch('displayName', nil)
      user.photo_url = api_response.fetch('photoUrl', nil)
      user.provider_id = api_response.fetch('provider_id',
          api_response.fetch('providerId', nil))
      user.email_verified = api_response.fetch('emailVerified',
          api_response.fetch('verified', nil))
      user.password_hash = api_response.fetch('passwordHash', nil)
      user.salt = api_response.fetch('salt', nil)
      user.password = api_response.fetch('password', nil)
      user.provider_info = api_response.fetch('providerUserInfo', {})
      user
    end

    # Convert to gitkit api request (a dict)
    def to_request
      request = {}
      request['email'] = @email if @email
      request['localId'] = @user_id if @user_id
      request['displayName'] = @name if @name
      request['photoUrl'] = @photo_url if @photo_url
      request['emailVerified'] = @email_verified if @email_verified != nil
      request['passwordHash'] =
          JWT.base64url_encode @password_hash if @password_hash
      request['salt'] = JWT.base64url_encode @salt if @salt
      request['providerUserInfo'] = @provider_info if @provider_info != nil
      request
    end
  end

  class GitkitClientError < StandardError
    def initialize(message)
      super
    end
  end

  class GitkitServerError < StandardError
    def initialize(message)
      super
    end
  end
end
