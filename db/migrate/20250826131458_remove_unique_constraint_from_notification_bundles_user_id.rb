class RemoveUniqueConstraintFromNotificationBundlesUserId < ActiveRecord::Migration[8.1]
  def change
    remove_index :notification_bundles, :user_id, unique: true
    add_index :notification_bundles, %i[ ends_at status ]
  end
end
