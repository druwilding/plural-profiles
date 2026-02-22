Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]
  resource :email_verification, only: :show

  # Authenticated user management of their own profiles and groups
  resources :our_profiles, path: "our/profiles", controller: "our/profiles" do
    member do
      delete :remove_from_group
    end
  end
  resources :our_groups, path: "our/groups", controller: "our/groups" do
    member do
      get :manage_profiles
      post :add_profile
      delete :remove_profile
      get :manage_groups
      post :add_group
      delete :remove_group
    end
  end
  resource :our_account, path: "our/account", controller: "our/account", only: %i[show] do
    patch :update_password
    patch :update_email
  end

  # Public shareable URLs (no auth required)
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

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "stats" => "stats#index"

  # Defines the root path route ("/")
  root "home#index"
end
