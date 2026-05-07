class AddHealthcheckDetailsToPings < ActiveRecord::Migration[8.1]
  def change
    add_reference :pings, :project, foreign_key: true
    add_column :pings, :status, :string
    add_column :pings, :http_status, :integer
    add_column :pings, :response_time_ms, :integer
    add_column :pings, :error, :string
    add_column :pings, :checked_at, :datetime

    add_index :pings, [ :project_id, :checked_at ]
  end
end
