require 'rpc_helper'
require 'mocha/test_unit'
require 'test/unit'
require 'test_data'

class RpcHelperTest < Test::Unit::TestCase

  def setup
    @rpc_helper = GitkitLib::RpcHelper.new('service-email',
        Base64.decode64(TestData::P12_KEY), 'server-api-key')
  end

  def test_client_error
    error_msg = 'invalid email'
    error_response = {
      'error' => {
        'code' => 400,
        'message' => error_msg
      }
    }
    begin
      @rpc_helper.check_gitkit_error error_response
      fail
    rescue GitkitLib::GitkitClientError => e
      assert_equal error_msg, e.message
    end
  end

  def test_server_error
    error_msg = 'http 500'
    error_response = {
      'error' => {
        'code' => 500,
        'message' => error_msg
      }
    }
    begin
      @rpc_helper.check_gitkit_error error_response
      fail
    rescue GitkitLib::GitkitServerError => e
      assert_equal error_msg, e.message
    end
  end

  def test_get_access_token_first
    now_time = 10000
    Time.any_instance.stubs(:to_i).returns(now_time)
    token_response = Faraday::Response.new
    token_response.finish({:body => '{"access_token": "token"}'})
    Faraday::Connection.any_instance.expects(:post).returns(token_response)

    assert_equal 'token', @rpc_helper.fetch_access_token
    assert_equal now_time, @rpc_helper.token_issued_at
  end

  def test_get_access_token_cached
    @rpc_helper.access_token = 'token'
    @rpc_helper.token_issued_at = 10000
    # simulate the moment of 50 seconds -before- token expires
    now_time = @rpc_helper.token_issued_at + @rpc_helper.token_duration - 50
    Time.any_instance.stubs(:to_i).returns(now_time)
    # token should be cached
    assert_equal 'token', @rpc_helper.fetch_access_token
  end

  def test_get_access_token_expired
    @rpc_helper.access_token = 'token'
    @rpc_helper.token_issued_at = 10000
    # simulate the moment of 50 seconds -after- token expired
    now_time = @rpc_helper.token_issued_at + @rpc_helper.token_duration + 50
    Time.any_instance.stubs(:to_i).returns(now_time)
    # should get a new token
    new_token = 'new-token'
    token_response = Faraday::Response.new
    token_response.finish({:body => '{"access_token": "' + new_token + '"}'})
    Faraday::Connection.any_instance.expects(:post).returns(token_response)

    assert_equal new_token, @rpc_helper.fetch_access_token
  end
end

