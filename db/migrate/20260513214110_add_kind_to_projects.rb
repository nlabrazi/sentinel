class AddKindToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :kind, :string, null: false, default: "app"
    add_index :projects, :kind
  end
end
