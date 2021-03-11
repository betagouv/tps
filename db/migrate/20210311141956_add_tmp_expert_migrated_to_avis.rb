class AddTmpExpertMigratedToAvis < ActiveRecord::Migration[6.0]
  def change
    add_column :avis, :tmp_expert_migrated, :boolean, default: false
  end
end
