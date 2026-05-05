Rails.application.routes.draw do
  devise_for :users, only: [ :sessions ]
  get "pages/deploys"
  get "pages/settings"
  root "dashboard#index"
  resources :projects, only: [ :show ] do
    member do
      post :deploy
      patch :toggle_maintenance
      post :refresh_screenshot
    end
  end
  # Des routes pour les pages de navigation placeholder (optionnel, on peut les faire en simple lien statique)
  get "/deploys", to: "pages#deploys", as: :deploys
  get "/settings", to: "pages#settings", as: :settings
end
