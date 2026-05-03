Rails.application.routes.draw do
  root "dashboard#index"
  resources :projects, only: [:index, :show] do
    member do
      post :deploy
      patch :toggle_maintenance
    end
  end
end
