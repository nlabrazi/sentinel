class CreatePings < ActiveRecord::Migration[8.1]
  def change
    create_table :pings do |t|
      t.string :name

      t.timestamps
    end
  end
end
