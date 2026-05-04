class AddScreenshotUrlToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :screenshot_url, :string
  end
end
