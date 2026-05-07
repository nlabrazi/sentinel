Rails.application.routes.draw do
  devise_for :users, only: [ :sessions ]
  root "dashboard#index"
  resources :projects, only: [ :show ] do
    member do
      post :deploy
      patch :toggle_maintenance
      post :refresh_screenshot
      post :refresh_github_commits
    end
  end
  resources :deployments, only: [ :show ]
  get "/deploys", to: "pages#deploys", as: :deploys
  get "/settings", to: "pages#settings", as: :settings
  get "/documentation", to: "pages#documentation", as: :documentation
end
