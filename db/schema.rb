# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_22_132128) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "group_groups", force: :cascade do |t|
    t.bigint "child_group_id", null: false
    t.datetime "created_at", null: false
    t.bigint "parent_group_id", null: false
    t.datetime "updated_at", null: false
    t.index ["child_group_id"], name: "index_group_groups_on_child_group_id"
    t.index ["parent_group_id", "child_group_id"], name: "index_group_groups_on_parent_group_id_and_child_group_id", unique: true
    t.index ["parent_group_id"], name: "index_group_groups_on_parent_group_id"
  end

  create_table "group_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "profile_id"], name: "index_group_profiles_on_group_id_and_profile_id", unique: true
    t.index ["group_id"], name: "index_group_profiles_on_group_id"
    t.index ["profile_id"], name: "index_group_profiles_on_profile_id"
  end

  create_table "groups", force: :cascade do |t|
    t.string "avatar_alt_text"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index ["user_id"], name: "index_groups_on_user_id"
    t.index ["uuid"], name: "index_groups_on_uuid", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.string "avatar_alt_text"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "pronouns"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index ["user_id"], name: "index_profiles_on_user_id"
    t.index ["uuid"], name: "index_profiles_on_uuid", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "email_verified_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "group_groups", "groups", column: "child_group_id"
  add_foreign_key "group_groups", "groups", column: "parent_group_id"
  add_foreign_key "group_profiles", "groups"
  add_foreign_key "group_profiles", "profiles"
  add_foreign_key "groups", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "sessions", "users"
end
