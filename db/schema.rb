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

ActiveRecord::Schema[8.1].define(version: 2026_09_25_090000) do
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

  create_table "chat_channel_default_postables", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.bigint "postable_id", null: false
    t.string "postable_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["channel_id", "user_id"], name: "index_chat_channel_default_postables_on_channel_id_and_user_id", unique: true
    t.index ["postable_type", "postable_id"], name: "idx_on_postable_type_postable_id_f889e21558"
  end

  create_table "chat_channel_reads", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "channel_id"], name: "index_chat_channel_reads_on_user_id_and_channel_id", unique: true
  end

  create_table "chat_channels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.bigint "server_id", null: false
    t.string "subtitle"
    t.bigint "theme_id"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["server_id", "name"], name: "index_chat_channels_on_server_id_and_name", unique: true
    t.index ["theme_id"], name: "index_chat_channels_on_theme_id"
    t.index ["uuid"], name: "index_chat_channels_on_uuid", unique: true
  end

  create_table "chat_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_postable_id"
    t.string "default_postable_type"
    t.string "role", default: "member", null: false
    t.bigint "server_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["default_postable_type", "default_postable_id"], name: "idx_on_default_postable_type_default_postable_id_782e0a1134"
    t.index ["server_id", "user_id"], name: "index_chat_memberships_on_server_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_chat_memberships_on_user_id"
  end

  create_table "chat_messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.bigint "postable_id"
    t.string "postable_name", null: false
    t.string "postable_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["channel_id", "created_at"], name: "index_chat_messages_on_channel_id_and_created_at"
    t.index ["postable_type", "postable_id"], name: "index_chat_messages_on_postable"
    t.index ["user_id"], name: "index_chat_messages_on_user_id"
  end

  create_table "chat_server_invites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.datetime "redeemed_at"
    t.bigint "redeemed_by_id"
    t.bigint "server_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_chat_server_invites_on_created_by_id"
    t.index ["redeemed_by_id"], name: "index_chat_server_invites_on_redeemed_by_id"
    t.index ["server_id"], name: "index_chat_server_invites_on_server_id"
    t.index ["token"], name: "index_chat_server_invites_on_token", unique: true
  end

  create_table "chat_servers", force: :cascade do |t|
    t.string "avatar_alt_text"
    t.string "avatar_shape", default: "rounded", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.string "subtitle"
    t.bigint "theme_id"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["owner_id"], name: "index_chat_servers_on_owner_id"
    t.index ["theme_id"], name: "index_chat_servers_on_theme_id"
    t.index ["uuid"], name: "index_chat_servers_on_uuid", unique: true
  end

  create_table "duplication_wizards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.jsonb "state", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["group_id"], name: "index_duplication_wizards_on_group_id"
    t.index ["user_id"], name: "index_duplication_wizards_on_user_id"
  end

  create_table "emote_aliases", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "emote_id", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_emote_aliases_on_code", unique: true
    t.index ["emote_id"], name: "index_emote_aliases_on_emote_id"
  end

  create_table "emote_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "owner_type"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "name"], name: "index_emote_groups_on_owner_type_and_owner_id_and_name", unique: true
    t.index ["owner_type", "owner_id"], name: "index_emote_groups_on_owner"
  end

  create_table "emotes", force: :cascade do |t|
    t.datetime "archived_at"
    t.string "code", null: false
    t.boolean "code_overridden", default: false, null: false
    t.datetime "created_at", null: false
    t.bigint "emote_group_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_emotes_on_code", unique: true
    t.index ["emote_group_id"], name: "index_emotes_on_emote_group_id"
    t.index ["name"], name: "index_emotes_on_name", unique: true
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
    t.string "avatar_shape", default: "rounded", null: false
    t.string "chat_bracket_after"
    t.string "chat_bracket_before"
    t.bigint "copied_from_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "emotes"
    t.jsonb "labels", default: [], null: false
    t.string "mini_profile_avatar_alt_text"
    t.boolean "mini_profile_avatar_inherited", default: true, null: false
    t.string "mini_profile_avatar_shape", default: "rounded", null: false
    t.text "mini_profile_description"
    t.boolean "mini_profile_description_inherited", default: false, null: false
    t.string "mini_profile_emotes"
    t.boolean "mini_profile_emotes_inherited", default: true, null: false
    t.boolean "mini_profile_link_enabled", default: false, null: false
    t.string "mini_profile_name"
    t.boolean "mini_profile_name_inherited", default: true, null: false
    t.string "mini_profile_pronouns"
    t.boolean "mini_profile_pronouns_inherited", default: true, null: false
    t.string "mini_profile_subtitle"
    t.boolean "mini_profile_subtitle_inherited", default: true, null: false
    t.string "mini_profile_tag_line"
    t.boolean "mini_profile_tag_line_inherited", default: true, null: false
    t.string "name", null: false
    t.string "pronouns"
    t.string "subtitle"
    t.string "tag_line"
    t.bigint "theme_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index "user_id, COALESCE(chat_bracket_before, ''::character varying), COALESCE(chat_bracket_after, ''::character varying)", name: "index_groups_on_user_id_and_chat_bracket_pair", unique: true, where: "((chat_bracket_before IS NOT NULL) OR (chat_bracket_after IS NOT NULL))"
    t.index ["copied_from_id"], name: "index_groups_on_copied_from_id"
    t.index ["labels"], name: "index_groups_on_labels", using: :gin
    t.index ["theme_id"], name: "index_groups_on_theme_id"
    t.index ["user_id"], name: "index_groups_on_user_id"
    t.index ["uuid"], name: "index_groups_on_uuid", unique: true
  end

  create_table "inclusion_overrides", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.jsonb "path", default: [], null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "path", "target_type", "target_id"], name: "idx_inclusion_overrides_unique", unique: true
    t.index ["group_id"], name: "index_inclusion_overrides_on_group_id"
  end

  create_table "invite_codes", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "redeemed_at"
    t.bigint "redeemed_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "upper((code)::text)", name: "index_invite_codes_on_upper_code", unique: true
    t.index ["redeemed_by_id"], name: "index_invite_codes_on_redeemed_by_id"
    t.index ["user_id"], name: "index_invite_codes_on_user_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.string "avatar_alt_text"
    t.string "avatar_shape", default: "rounded", null: false
    t.string "chat_bracket_after"
    t.string "chat_bracket_before"
    t.bigint "copied_from_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "emotes"
    t.jsonb "labels", default: [], null: false
    t.string "mini_profile_avatar_alt_text"
    t.boolean "mini_profile_avatar_inherited", default: true, null: false
    t.string "mini_profile_avatar_shape", default: "rounded", null: false
    t.text "mini_profile_description"
    t.boolean "mini_profile_description_inherited", default: false, null: false
    t.string "mini_profile_emotes"
    t.boolean "mini_profile_emotes_inherited", default: true, null: false
    t.boolean "mini_profile_link_enabled", default: false, null: false
    t.string "mini_profile_name"
    t.boolean "mini_profile_name_inherited", default: true, null: false
    t.string "mini_profile_pronouns"
    t.boolean "mini_profile_pronouns_inherited", default: true, null: false
    t.string "mini_profile_subtitle"
    t.boolean "mini_profile_subtitle_inherited", default: true, null: false
    t.string "mini_profile_tag_line"
    t.boolean "mini_profile_tag_line_inherited", default: true, null: false
    t.string "name", null: false
    t.string "pronouns"
    t.string "subtitle"
    t.string "tag_line"
    t.bigint "theme_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index "user_id, COALESCE(chat_bracket_before, ''::character varying), COALESCE(chat_bracket_after, ''::character varying)", name: "index_profiles_on_user_id_and_chat_bracket_pair", unique: true, where: "((chat_bracket_before IS NOT NULL) OR (chat_bracket_after IS NOT NULL))"
    t.index ["copied_from_id"], name: "index_profiles_on_copied_from_id"
    t.index ["labels"], name: "index_profiles_on_labels", using: :gin
    t.index ["theme_id"], name: "index_profiles_on_theme_id"
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

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "themes", force: :cascade do |t|
    t.string "background_attachment", default: "scroll", null: false
    t.string "background_position", default: "center", null: false
    t.string "background_repeat", default: "repeat", null: false
    t.string "background_size", default: "auto", null: false
    t.jsonb "colors", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "credit", limit: 255
    t.string "credit_url", limit: 255
    t.string "name", null: false
    t.text "notes"
    t.boolean "shared", default: false, null: false
    t.boolean "site_default", default: false, null: false
    t.string "tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["shared"], name: "index_themes_on_shared", where: "(shared = true)"
    t.index ["site_default"], name: "index_themes_on_site_default_unique", unique: true, where: "(site_default = true)"
    t.index ["tags"], name: "index_themes_on_tags", using: :gin
    t.index ["user_id"], name: "index_themes_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "active_theme_id"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "email_address", null: false
    t.datetime "email_verified_at"
    t.boolean "override_themes", default: false, null: false
    t.string "password_digest", null: false
    t.string "time_zone"
    t.string "unverified_email_address"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index "lower((username)::text)", name: "index_users_on_lower_username", unique: true
    t.index ["active_theme_id"], name: "index_users_on_active_theme_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chat_channel_default_postables", "chat_channels", column: "channel_id"
  add_foreign_key "chat_channel_default_postables", "users"
  add_foreign_key "chat_channel_reads", "chat_channels", column: "channel_id"
  add_foreign_key "chat_channel_reads", "users"
  add_foreign_key "chat_channels", "chat_servers", column: "server_id"
  add_foreign_key "chat_channels", "themes", on_delete: :nullify
  add_foreign_key "chat_memberships", "chat_servers", column: "server_id"
  add_foreign_key "chat_memberships", "users"
  add_foreign_key "chat_messages", "chat_channels", column: "channel_id"
  add_foreign_key "chat_messages", "users"
  add_foreign_key "chat_server_invites", "chat_servers", column: "server_id"
  add_foreign_key "chat_server_invites", "users", column: "created_by_id"
  add_foreign_key "chat_server_invites", "users", column: "redeemed_by_id"
  add_foreign_key "chat_servers", "themes", on_delete: :nullify
  add_foreign_key "chat_servers", "users", column: "owner_id"
  add_foreign_key "duplication_wizards", "groups"
  add_foreign_key "duplication_wizards", "users"
  add_foreign_key "emote_aliases", "emotes"
  add_foreign_key "emotes", "emote_groups"
  add_foreign_key "group_groups", "groups", column: "child_group_id"
  add_foreign_key "group_groups", "groups", column: "parent_group_id"
  add_foreign_key "group_profiles", "groups"
  add_foreign_key "group_profiles", "profiles"
  add_foreign_key "groups", "groups", column: "copied_from_id"
  add_foreign_key "groups", "themes", on_delete: :nullify
  add_foreign_key "groups", "users"
  add_foreign_key "inclusion_overrides", "groups", on_delete: :cascade
  add_foreign_key "invite_codes", "users"
  add_foreign_key "invite_codes", "users", column: "redeemed_by_id"
  add_foreign_key "profiles", "profiles", column: "copied_from_id"
  add_foreign_key "profiles", "themes", on_delete: :nullify
  add_foreign_key "profiles", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "themes", "users"
  add_foreign_key "users", "themes", column: "active_theme_id", on_delete: :nullify
end
