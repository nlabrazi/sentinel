require "set"

class AddUsernameToUsers < ActiveRecord::Migration[8.1]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    add_column :users, :username, :string

    MigrationUser.reset_column_information
    used_usernames = Set.new

    MigrationUser.find_each do |user|
      base_username = user.email.to_s.split("@").first.presence || "user"
      username = base_username.parameterize(separator: "_").presence || "user"

      if used_usernames.include?(username) || MigrationUser.where(username: username).where.not(id: user.id).exists?
        username = "#{username}_#{user.id}"
      end

      used_usernames.add(username)
      user.update_columns(username: username)
    end

    change_column_null :users, :username, false
    add_index :users, :username, unique: true
  end

  def down
    remove_index :users, :username
    remove_column :users, :username
  end
end
