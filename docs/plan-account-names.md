# Plan: Account Names

## Summary

Add an optional **account name** to user accounts so people can connect with each other without revealing their email address. The column is called `username` in the data model but displayed as **"Account name"** in all UI — the same convention we follow with `User` → "account".

Account names enable future features like friendship, theme sharing, and access grants.

## Decisions

| Question   | Decision                                                                                |
| ---------- | --------------------------------------------------------------------------------------- |
| UI label   | "Account name" (column: `username`)                                                     |
| Required?  | Optional forever — never enforced                                                       |
| On signup? | Shown as an optional field                                                              |
| Format     | 2–30 chars, `a-z 0-9 _ -`, case-insensitive, no leading/trailing/consecutive `_` or `-` |
| Login      | Accept either email address or account name                                             |

## Format rules

- **Length**: 2–30 characters
- **Characters**: lowercase Latin letters (`a-z`), digits (`0-9`), underscores (`_`), hyphens (`-`)
- **Restrictions**: must not start or end with `_` or `-`; no consecutive `_` or `-` (e.g. `a__b`, `a--b`, `a-_b` are all invalid)
- **Case**: normalised to lowercase on save; uniqueness is case-insensitive
- **Regex**: `\A[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?\z` combined with a rejection of consecutive `[_-]{2}` via a second check (or a single pattern: `\A[a-z0-9]([a-z0-9]*[_-]?[a-z0-9])*\z` — test carefully)

A simpler way to express it in the model:

```ruby
USERNAME_FORMAT = /\A[a-z0-9](?:[a-z0-9]|[_-](?=[a-z0-9]))*[a-z0-9]?\z/
```

This enforces: starts with alphanumeric, every `_` or `-` must be followed by an alphanumeric, ends with alphanumeric. The `?` after the last group allows two-character names like `"ab"`. Test with edge cases:

| Input      | Valid?               |
| ---------- | -------------------- |
| `ab`       | ✓                    |
| `a`        | ✗ (too short)        |
| `abc-def`  | ✓                    |
| `abc_def`  | ✓                    |
| `abc--def` | ✗                    |
| `_abc`     | ✗                    |
| `abc-`     | ✗                    |
| `abc_-def` | ✗                    |
| `ABC`      | normalised → `abc` ✓ |

## Implementation steps

### Step 1 — Migration

```ruby
class AddUsernameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :username, :string
    add_index :users, "lower(username)", unique: true, name: "index_users_on_lower_username"
  end
end
```

The expression index on `lower(username)` guarantees uniqueness regardless of case at the database level. `NULL` values are excluded from unique indexes in PostgreSQL, so multiple users can have no account name.

### Step 2 — Model changes (`User`)

Add to `app/models/user.rb`:

```ruby
# Normalise username: strip whitespace, downcase
normalizes :username, with: ->(u) { u.strip.downcase }, apply_to_nil: false

# Format constant
USERNAME_FORMAT = /\A[a-z0-9](?:[a-z0-9]|[_-](?=[a-z0-9]))*[a-z0-9]?\z/

# Validations (all allow_blank since it's optional)
validates :username,
  length: { minimum: 2, maximum: 30 },
  format: { with: USERNAME_FORMAT, message: "can only contain lowercase letters, numbers, underscores, and hyphens (no leading/trailing/consecutive special characters)" },
  uniqueness: { case_sensitive: false },
  allow_blank: true
```

Note: `allow_blank: true` means `nil` and `""` both skip validation. The normalizer won't fire for `nil` (due to `apply_to_nil: false`). An empty string submission should collapse to `nil` — add a normalizer or handle it in the controller:

```ruby
normalizes :username, with: ->(u) { value = u.strip.downcase; value.blank? ? nil : value }, apply_to_nil: false
```

### Step 3 — Login with account name or email

#### View: `app/views/sessions/new.html.haml`

Change the email field to a generic text field:

```haml
.form-group
  = form.label :login, "Email address or account name"
  = form.text_field :login, required: true, autocomplete: "username", value: params[:login]
```

#### Controller: `app/controllers/sessions_controller.rb`

```ruby
def create
  login = params[:login].to_s.strip
  user = if login.include?("@")
    User.authenticate_by(email_address: login, password: params[:password])
  else
    user_by_name = User.where("lower(username) = ?", login.downcase).first
    user_by_name&.authenticate(params[:password]) || nil
  end

  if user && !user.deactivated?
    start_new_session_for user
    redirect_to after_authentication_url
  else
    redirect_to new_session_path, alert: "Try another email address or password."
  end
end
```

Key points:
- If the input contains `@`, treat it as an email address and use `authenticate_by` (which handles timing-safe comparison)
- Otherwise, look up by `lower(username)` and call `authenticate` on the found user
- To keep timing-safe behaviour for username login too, consider always doing `User.authenticate_by` with a constructed `email_address` from the found user, or use `BCrypt`'s constant-time comparison. The simplest timing-safe approach:

```ruby
def create
  login = params[:login].to_s.strip
  password = params[:password].to_s

  if login.include?("@")
    user = User.authenticate_by(email_address: login, password: password)
  else
    found = User.where("lower(username) = ?", login.downcase).first
    # authenticate_by is timing-safe; fall back to a fake check to prevent timing leaks
    user = if found
      User.authenticate_by(email_address: found.email_address, password: password)
    else
      User.authenticate_by(email_address: "nobody@invalid", password: password)
      nil
    end
  end

  if user && !user.deactivated?
    start_new_session_for user
    redirect_to after_authentication_url
  else
    redirect_to new_session_path, alert: "Try another email address or password."
  end
end
```

### Step 4 — Signup form

#### View: `app/views/registrations/new.html.haml`

After the invite code section and before the email field, add:

```haml
.form-group
  = form.label :username, "Account name (optional)"
  = form.text_field :username, autocomplete: "username", minlength: 2, maxlength: 30, pattern: "[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]|[a-zA-Z0-9]{2}", title: "2-30 characters: letters, numbers, underscores, hyphens"
  %p.form-hint You can add one later from the account page.
```

#### Controller: `app/controllers/registrations_controller.rb`

Add `:username` to the permitted params:

```ruby
def registration_params
  params.require(:user).permit(:email_address, :password, :password_confirmation, :username)
end
```

### Step 5 — Account page

#### Route: `config/routes.rb`

Add a new action to the account resource:

```ruby
resource :our_account, path: "our/account", controller: "our/account", only: %i[show] do
  patch :update_password
  patch :update_email
  delete :cancel_email_change
  patch :update_preferences
  patch :update_username  # ← new
end
```

#### Controller: `app/controllers/our/account_controller.rb`

```ruby
def update_username
  if Current.user.update(username_params)
    redirect_to our_account_path, notice: "Account name updated."
  else
    # Re-render with errors
    render :show, status: :unprocessable_entity
  end
end

private

def username_params
  params.require(:user).permit(:username)
end
```

#### View: `app/views/our/account/show.html.haml`

Add a new card at the top of the page (account name is identity-level, so it should be prominent):

```haml
.card
  %h2 Account name
  - if Current.user.username.present?
    %p
      Current account name:
      %strong= Current.user.username
  - else
    %p You haven't set an account name yet. An account name lets others find and connect with you without sharing your email address.

  = form_with model: Current.user, url: update_username_our_account_path, method: :patch do |form|
    - if Current.user.errors[:username].any?
      .error-messages
        - Current.user.errors.full_messages_for(:username).each do |message|
          %p= message

    .form-group
      = form.label :username, "Account name"
      = form.text_field :username, minlength: 2, maxlength: 30, autocomplete: "username"
      %p.form-hint 2–30 characters: letters, numbers, underscores, and hyphens.

    .form-group
      = form.submit Current.user.username? ? "Change account name" : "Set account name"
```

### Step 6 — Tests

#### Model tests (`test/models/user_test.rb`)

```ruby
# --- Username tests ---

test "username is optional" do
  user = users(:one) # or however your fixture is named
  user.username = nil
  assert user.valid?
end

test "username is normalised to lowercase" do
  user = users(:one)
  user.username = "  FooBar  "
  user.valid?
  assert_equal "foobar", user.username
end

test "blank username becomes nil" do
  user = users(:one)
  user.username = "   "
  user.valid?
  assert_nil user.username
end

test "valid usernames" do
  user = users(:one)
  %w[ab abc abc123 foo-bar foo_bar a1 a-b a_b abcdefghijklmnopqrstuvwxyz1234].each do |name|
    user.username = name
    assert user.valid?, "Expected '#{name}' to be valid but got: #{user.errors.full_messages}"
  end
end

test "invalid usernames" do
  user = users(:one)
  ["a", "_abc", "abc_", "-abc", "abc-", "a__b", "a--b", "a-_b", "ab cd", "ab@cd", "ab.cd", "a" * 31].each do |name|
    user.username = name
    assert_not user.valid?, "Expected '#{name}' to be invalid"
  end
end

test "username must be unique case-insensitively" do
  users(:one).update!(username: "taken")
  user = users(:two)
  user.username = "TAKEN"
  assert_not user.valid?
  assert_includes user.errors[:username], "has already been taken"
end
```

#### Controller tests (`test/controllers/sessions_controller_test.rb`)

```ruby
test "login with email address" do
  post session_path, params: { login: users(:one).email_address, password: "password" }
  assert_redirected_to root_path # or wherever after_authentication_url goes
end

test "login with account name" do
  users(:one).update!(username: "testuser")
  post session_path, params: { login: "testuser", password: "password" }
  assert_redirected_to root_path
end

test "login with account name is case-insensitive" do
  users(:one).update!(username: "testuser")
  post session_path, params: { login: "TestUser", password: "password" }
  assert_redirected_to root_path
end

test "login with wrong password for account name fails" do
  users(:one).update!(username: "testuser")
  post session_path, params: { login: "testuser", password: "wrongpassword" }
  assert_redirected_to new_session_path
end
```

#### Account controller tests (`test/controllers/our/account_controller_test.rb`)

```ruby
test "set account name" do
  sign_in users(:one)
  patch update_username_our_account_path, params: { user: { username: "newname" } }
  assert_redirected_to our_account_path
  assert_equal "newname", users(:one).reload.username
end

test "clear account name" do
  users(:one).update!(username: "oldname")
  sign_in users(:one)
  patch update_username_our_account_path, params: { user: { username: "" } }
  assert_redirected_to our_account_path
  assert_nil users(:one).reload.username
end

test "invalid account name shows errors" do
  sign_in users(:one)
  patch update_username_our_account_path, params: { user: { username: "_bad" } }
  assert_response :unprocessable_entity
end
```

#### System tests

Add a system test for the account name flow (set, change, login with it). Test the signup flow with an optional account name.

## Future considerations

- **Reserved names**: consider blocking names like `admin`, `support`, `help`, `our`, `api`, `system`, `null`, `undefined`, etc. A simple `RESERVED_USERNAMES` constant with a custom validation would work.
- **Display name vs. account name**: The account name is for identification/lookup. Profile names already serve as display names.
- **Rate limiting**: The login endpoint is already rate-limited, which covers username-based login too.
- **Account name in URLs**: Currently not needed. If we later want `/@username` style URLs, the format is already URL-safe.
- **Clearing an account name**: Decide whether clearing a name should be allowed if features depend on it (e.g. active friendships). For now it's fine since no features depend on it yet.
