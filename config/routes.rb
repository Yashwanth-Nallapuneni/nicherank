Rails.application.routes.draw do
  root "rankings#index"
  resources :professors, only: :show
  get "up" => "rails/health#show", as: :rails_health_check
end
