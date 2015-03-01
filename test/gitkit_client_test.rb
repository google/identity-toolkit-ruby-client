require 'base64'
require 'gitkit_client'
require 'mocha/test_unit'
require 'test/unit'
require 'test_data'

class GitkitClientTest < Test::Unit::TestCase

  def setup
    GitkitLib::GitkitClient.any_instance.stubs(:get_certs).
        returns(TestData::CERTS)
  end

  def test_verify_token_valid
    Time.any_instance.stubs(:to_i).returns(0)
    gitkit_client = GitkitLib::GitkitClient.new(
        '924226504183.apps.googleusercontent.com',
        'service_email',
        Base64.decode64(TestData::P12_KEY),
        'widget_url',
        'server-api-key')
    user = gitkit_client.verify_gitkit_token TestData::TOKEN
    assert_equal '1234@example.com', user.email
    assert_equal '1234', user.user_id
  end

  def test_verify_token_expired
    Time.any_instance.stubs(:to_i).returns(9876543210)
    gitkit_client = GitkitLib::GitkitClient.new(
        '924226504183.apps.googleusercontent.com',
        'service_email',
        Base64.decode64(TestData::P12_KEY),
        'widget_url',
        'server-api-key')
    user,error = gitkit_client.verify_gitkit_token TestData::TOKEN
    assert_nil user
    assert_equal error, 'token expired'
  end

  def test_verify_token_audience_mismatch
    Time.any_instance.stubs(:to_i).returns(0)
    gitkit_client = GitkitLib::GitkitClient.new(
        'a-different-client-id.apps.googleusercontent.com',
        'service_email',
        Base64.decode64(TestData::P12_KEY),
        'widget_url',
        'server-api-key')
    user,error = gitkit_client.verify_gitkit_token TestData::TOKEN
    assert_nil user
    assert_equal error, 'audience mismatch'
  end

  def test_download_account
    page1 = [
        {'email' => 'email-1', 'localId' => 'user-1'},
        {'email' => 'email-2', 'localId' => 'user-2'}]
    page2 = [
        {'email' => 'email-3', 'localId' => 'user-3'}]
    stub = GitkitLib::RpcHelper.any_instance
    stub.expects(:download_account).with(nil, 2).returns(['page2_token', page1])
    stub.expects(:download_account).with('page2_token', 2).returns([nil, page2])

    gitkit_client = GitkitLib::GitkitClient.new(
        '924226504183.apps.googleusercontent.com',
        'service_email',
        Base64.decode64(TestData::P12_KEY),
        'widget_url',
        'server-api-key')
    index = 0
    gitkit_client.get_all_users(2) { |account|
      index = index + 1
      assert_equal 'user-' + index.to_s, account.user_id
    }
    assert_equal 3, index
  end

  def test_get_oob_response
    stub = GitkitLib::RpcHelper.any_instance
    stub.expects(:get_oob_code).returns('oob-code')
    gitkit_client = GitkitLib::GitkitClient.new(
        '924226504183.apps.googleusercontent.com',
        'service_email',
        Base64.decode64(TestData::P12_KEY),
        'http://localhost:1234/widget',
        'server-api-key')
    oob_req = {
        'action' => 'resetPassword',
        'email' => 'user@example.com',
        'challenge' => 'what is the number',
        'response' => '100'}
    oob_result = gitkit_client.get_oob_result(oob_req, '1.1.1.1')
    assert_equal oob_req['email'], oob_result[:email]
    assert_equal :RESET_PASSWORD, oob_result[:action]
    assert_equal(
        'http://localhost:1234/widget?mode=resetPassword&oobCode=oob-code',
        oob_result[:oobLink])
  end

  def test_email_verification_link
    stub = GitkitLib::RpcHelper.any_instance
    stub.expects(:get_oob_code).returns('oob-code')
    gitkit_client = GitkitLib::GitkitClient.new(
        '924226504183.apps.googleusercontent.com',
        'service_email',
        Base64.decode64(TestData::P12_KEY),
        'http://localhost:1234/widget',
        'server-api-key')
    oob_link = gitkit_client.get_email_verification_link('user@example.com')
    assert_equal(
        'http://localhost:1234/widget?mode=verifyEmail&oobCode=oob-code',
        oob_link)
  end
end

