class RemoveScreenshotUrlFromProjects < ActiveRecord::Migration[8.1]
  def change
    remove_column :projects, :screenshot_url, :string
  end
end
