class AddIndexToInviteCodesRedeemedById < ActiveRecord::Migration[8.1]
  def change
    add_index :invite_codes, :redeemed_by_id
  end
end
