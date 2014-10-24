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

require 'jwt'
require 'multi_json'
require 'faraday'
require 'gitkit_client'
require 'openssl'

module GitkitLib
  class RpcHelper
    attr_accessor :access_token, :token_issued_at, :token_duration

    TOKEN_ENDPOINT = 'https://accounts.google.com/o/oauth2/token'
    GITKIT_SCOPE = 'https://www.googleapis.com/auth/identitytoolkit'
    GITKIT_API_URL =
        'https://www.googleapis.com/identitytoolkit/v3/relyingparty/'

    def initialize(service_account_email, service_account_key, server_api_key,
        google_token_endpoint = TOKEN_ENDPOINT)
      @service_account_email = service_account_email
      @google_api_url = google_token_endpoint
      @connection = Faraday::Connection.new
      @service_account_key =
          OpenSSL::PKCS12.new(service_account_key, 'notasecret').key
      @server_api_key = server_api_key
      @token_duration = 3600
      @token_issued_at = 0
      @access_token = nil
    end

    # GetAccountInfo by email
    #
    # @api private
    # @param [String] email account email to be queried
    # @return [JSON] account info
    def get_user_by_email(email)
      invoke_gitkit_api('getAccountInfo', {'email' => [email]})
    end

    # GetAccountInfo by id
    #
    # @api private
    # @param [String] id account id to be queried
    # @return [JSON] account info
    def get_user_by_id(id)
      invoke_gitkit_api('getAccountInfo', {'localId' => [id]})
    end

    # Get out-of-band code for ResetPassword/ChangeEmail etc. operation
    #
    # @api private
    # @param [Hash<String, String>] request the oob request
    # @return <String> the oob code
    def get_oob_code(request)
      response = invoke_gitkit_api('getOobConfirmationCode', request)
      response.fetch('oobCode', nil)
    end

    # Download all accounts
    #
    # @api private
    # @param [String] next_page_token pagination token for next page
    # @param [Fixnum] max_results pagination size
    # @return [Array<JSON>] user account info
    def download_account(next_page_token, max_results)
      param = {}
      if next_page_token
        param['nextPageToken'] = next_page_token
      end
      if max_results
        param['maxResults'] = max_results
      end
      response = invoke_gitkit_api('downloadAccount', param)
      return response.fetch('nextPageToken', nil), response.fetch('users', {})
    end

    # Delete an account
    #
    # @api private
    # @param <String> local_id user id to be deleted
    def delete_account(local_id)
      invoke_gitkit_api('deleteAccount', {'localId' => local_id})
    end

    # Upload batch accounts
    #
    # @api private
    # @param <String> hash_algorithm hash algorithm
    # @param <String> hash_key hash key
    # @param <Array<GitkitUser>> accounts account to be uploaded
    def upload_account(hash_algorithm, hash_key, accounts)
      param = {
          'hashAlgorithm' => hash_algorithm,
          'signerKey' => hash_key,
          'users' => accounts
      }
      invoke_gitkit_api('uploadAccount', param)
    end

    # Creates a signed jwt assertion
    #
    # @api private
    # @return [String] jwt assertion
    def sign_assertion
      now = Time.new
      assertion = {
          'iss' => @service_account_email,
          'scope' => GITKIT_SCOPE,
          'aud' => @google_api_url,
          'exp' => (now + @token_duration).to_i,
          'iat' => now.to_i
      }
      JWT.encode(assertion, @service_account_key, 'RS256')
    end

    # Get an access token, from Google server if cached one is expired
    #
    # @api private
    def fetch_access_token
      if is_token_expired
        assertion = sign_assertion
        post_body = {
            'assertion' => assertion,
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer'}
        headers = {'Content-type' => 'application/x-www-form-urlencoded'}
        response = @connection.post(RpcHelper::TOKEN_ENDPOINT, post_body,
            headers)
        @access_token = MultiJson.load(response.env[:body])['access_token']
        @token_issued_at = Time.new.to_i
      end
      @access_token
    end

    # Check whether the cached access token is expired
    #
    # @api private
    # @return <Boolean> whether the access token is expired
    def is_token_expired
      @access_token == nil ||
          Time.new.to_i > @token_issued_at + @token_duration - 30
    end

    # Invoke Gitkit API, with optional access token for service account
    # operations
    #
    # @api private
    # @param [String] method Gitkit API method name
    # @param [Hash<String, String>] params api request params
    # @param [bool] need_service_account whether the request needs to be
    # authenticated
    # @return <JSON> the Gitkit api response
    def invoke_gitkit_api(method, params, need_service_account=true)
      post_body = MultiJson.dump params
      headers = {'Content-type' => 'application/json'}
      if need_service_account
        @connection.authorization :Bearer, fetch_access_token
      end
      response = @connection.post(GITKIT_API_URL + method, post_body, headers)
      check_gitkit_error MultiJson.load(response.env[:body])
    end

    # Download the Gitkit public certs
    #
    # @api private
    # @return <JSON> the public certs
    def get_gitkit_certs
      if @server_api_key.nil?
        @connection.authorization :Bearer, fetch_access_token
        response = @connection.get(GITKIT_API_URL + 'publicKeys')
      else
        response = @connection.get [GITKIT_API_URL, 'publicKeys?key=',
            @server_api_key].join
      end
      MultiJson.load response.body
    end

    # Checks the Gitkit response
    #
    # @api private
    # @param [JSON] response the response received
    # @return [JSON] the response if no error
    def check_gitkit_error(response)
      if response.has_key? 'error'
        error = response['error']
        if error.has_key? 'code'
          code = error['code']
          raise GitkitClientError, error['message'] if code.to_s.match(/^4/)
          raise GitkitServerError, error['message']
        else
          raise GitkitServerError, 'null error code from Gitkit server'
        end
      else
        response
      end
    end
  end
end
