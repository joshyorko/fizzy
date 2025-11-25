require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "send_magic_link" do
    identity = identities(:david)

    assert_emails 1 do
      magic_link = identity.send_magic_link
      assert_not_nil magic_link
      assert_equal identity, magic_link.identity
    end
  end

  test "join" do
    identity = identities(:david)
    account = accounts(:initech)

    Current.without_account do
      assert_difference "User.count", 1 do
        identity.join(account)
      end

      user = account.users.find_by!(identity: identity)

      assert_not_nil user
      assert_equal identity, user.identity
      assert_equal identity.email_address, user.name
    end
  end
end
