Rails.application.routes.draw do
  root "rankings#index"
  get "faculty", to: "researchers#index", as: :faculty
  resources :professors, only: :show
  get "up" => "rails/health#show", as: :rails_health_check
end
