Rails.application.routes.draw do
  devise_for :users,
             only: [ :sessions, :omniauth_callbacks ],
             controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  root "dashboard#index"
  resources :projects, only: [ :show ] do
    member do
      post :deploy
      patch :toggle_maintenance
      patch :update_monitoring
      post :refresh_screenshot
      post :refresh_github_commits
      post :refresh_runtime
      post :refresh_cron_status
      post :refresh_umami
      post :quick_command
    end
  end
  resources :deployments, only: [ :show ]
  get "/deploys", to: "pages#deploys", as: :deploys
  get "/settings", to: "pages#settings", as: :settings
  post "/settings/trigger_healthcheck", to: "pages#trigger_healthcheck_all", as: :trigger_healthcheck_settings
  post "/settings/trigger_sync_github", to: "pages#trigger_sync_github_all", as: :trigger_sync_github_settings
  post "/settings/trigger_sync_cron", to: "pages#trigger_sync_cron_all", as: :trigger_sync_cron_settings
  post "/settings/trigger_sync_umami", to: "pages#trigger_sync_umami_all", as: :trigger_sync_umami_settings
  get "/documentation", to: "pages#documentation", as: :documentation
  match "/locale/:locale", to: "locales#update", via: [ :get, :post ], as: :switch_locale
end
