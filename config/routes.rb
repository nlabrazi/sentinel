Rails.application.routes.draw do
  devise_for :users, only: [ :sessions ]
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
    end
  end
  resources :deployments, only: [ :show ]
  get "/deploys", to: "pages#deploys", as: :deploys
  get "/settings", to: "pages#settings", as: :settings
  post "/settings/trigger_healthcheck", to: "pages#trigger_healthcheck_all", as: :trigger_healthcheck_settings
  post "/settings/trigger_sync_github", to: "pages#trigger_sync_github_all", as: :trigger_sync_github_settings
  post "/settings/trigger_sync_cron", to: "pages#trigger_sync_cron_all", as: :trigger_sync_cron_settings
  get "/documentation", to: "pages#documentation", as: :documentation
end
