require 'rubygems'
require 'gitkit_client'
require 'pp'

gitkit_client =
    GitkitLib::GitkitClient.create_from_config_file('gitkit-server-config.json')

# Upload two accounts with password

def calc_sha1(key, plain_text, salt)
  hmac = OpenSSL::HMAC.new key, 'sha1'
  hmac << plain_text
  hmac << salt
  hmac.digest
end

def create_users(hash_key)
  user1 = GitkitLib::GitkitUser.new
  user1.email = '1234@example.com'
  user1.user_id = '1234'
  user1.salt = 'salt-1'
  user1.password_hash = calc_sha1(hash_key, '1111', 'salt-1')

  user2 = GitkitLib::GitkitUser.new
  user2.email = '5678@example.com'
  user2.user_id = '5678'
  user2.salt = 'salt-2'
  user2.password_hash = calc_sha1(hash_key, '5555', 'salt-2')

  [user1, user2]
end

hash_key = 'hash-key'
users = create_users hash_key
print 'Uploading: '
pp users
gitkit_client.upload_users 'HMAC_SHA1', hash_key, users

# Get user by email
#pp gitkit_client.get_user_by_email(ARGV[0])

# Get user by id
#pp gitkit_client.get_user_by_id(ARGV[0])

# Delete a user
#gitkit_client.delete_user ARGV[0]

# Download all accounts
#gitkit_client.get_all_users() { |account| pp account}
