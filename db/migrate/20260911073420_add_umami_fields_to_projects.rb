class AddUmamiFieldsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :umami_website_id, :string
    add_column :projects, :umami_visitors_24h, :integer, default: 0
    add_column :projects, :umami_pageviews_24h, :integer, default: 0
    add_column :projects, :umami_bounce_rate, :integer
    add_column :projects, :umami_synced_at, :datetime
    add_column :projects, :umami_sync_error, :string

    add_index :projects, :umami_website_id
  end
end
