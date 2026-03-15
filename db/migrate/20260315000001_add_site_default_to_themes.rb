class AddSiteDefaultToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :site_default, :boolean, default: false, null: false
    add_index :themes, :site_default,
              unique: true,
              where: "site_default = true",
              name: "index_themes_on_site_default_unique"
  end
end
