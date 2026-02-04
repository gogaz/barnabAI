class CreateUserMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :user_mappings do |t|
      t.string :slack_user_id
      t.string :github_username
      t.string :first_name
      t.references :repository, null: false, foreign_key: true

      t.timestamps
    end
  end
end
