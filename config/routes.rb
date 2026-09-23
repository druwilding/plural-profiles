Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]
  resource :email_verification, only: :show

  # Authenticated user management of their own profiles and groups
  resources :our_profiles, path: "our/profiles", controller: "our/profiles" do
    member do
      delete :remove_from_group
      patch :regenerate_uuid
    end
  end
  resources :our_groups, path: "our/groups", controller: "our/groups" do
    member do
      get :manage_profiles
      post :add_profile
      delete :remove_profile
      post :add_group
      delete :remove_group
      patch :regenerate_uuid
      get :manage_groups
      patch :toggle_visibility
      get  :duplicate
      post :duplicate_scan
      get  :duplicate_resolve
      post :duplicate_resolve, action: :duplicate_resolve_post
      get  :duplicate_confirm
      post :duplicate_execute
    end
  end
  get "our/chat_identity/:postable_type/:postable_uuid/edit", to: "our/chat_identities#edit",
    as: :edit_our_chat_identity, constraints: { postable_type: /Profile|Group/ }
  patch "our/chat_identity/:postable_type/:postable_uuid", to: "our/chat_identities#update",
    as: :our_chat_identity, constraints: { postable_type: /Profile|Group/ }
  post "our/chat_identity/:postable_type/:postable_uuid/preview", to: "our/chat_identities#preview",
    as: :preview_our_chat_identity, constraints: { postable_type: /Profile|Group/ }

  resource :our_search, path: "our/search", controller: "our/search", only: %i[show]
  resource :our_account, path: "our/account", controller: "our/account", only: %i[show] do
    patch :update_password
    patch :update_email
    delete :cancel_email_change
    patch :update_preferences
    patch :update_time_zone
    patch :update_username
  end
  resources :our_invite_codes, path: "our/invite-codes", controller: "our/invite_codes", only: %i[create destroy]
  resources :our_themes, path: "our/themes", controller: "our/themes" do
    member do
      patch :activate
      patch :set_default
      post :duplicate
    end
    collection do
      patch :deactivate
    end
  end

  # Site-wide emote management (admins only)
  namespace :admin do
    resources :emotes, only: %i[index update destroy] do
      member do
        patch :archive
        patch :restore
        delete :remove_alias
      end
    end
    resources :emote_groups, only: %i[create update destroy] do
      member do
        patch :move
      end
    end
  end

  # Shareable UUID URLs (require authentication)
  resources :profiles, only: :show, param: :uuid
  resources :groups, only: :show, param: :uuid do
    member do
      get :panel
    end
    resources :profiles, only: :show, param: :uuid, controller: "group_profiles" do
      member do
        get :panel
      end
    end
  end

  constraints subdomain: "chat" do
    scope module: "chat", as: "chat" do
      root "servers#index"

      get "invite/:token", to: "invite_redemptions#show", as: :invite_redemption

      get "mini_profile/:postable_type/:postable_uuid", to: "mini_profiles#show",
        as: :mini_profile, constraints: { postable_type: /Profile|Group/ }

      resources :servers, only: %i[index show new create edit update], param: :uuid do
        member do
          get :join
          post :join
        end

        resource :invite, only: %i[show create], controller: "server_invites"
        resource :membership, only: %i[edit update], controller: "memberships"

        resources :channels, only: %i[show new create edit update], param: :uuid do
          member do
            patch :mark_read
          end
          resources :messages, only: %i[index create]
          resource :default_postable, only: :update, controller: "channel_default_postables"
        end
      end
    end
  end

  mount ActionCable.server => "/cable"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "stats" => "stats#index"

  # Defines the root path route ("/")
  root "home#index"
end
