Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  root "containers#index"

  resources :containers, only: [], controller: "container_actions" do
    member do
      post :start
      post :stop
      post :restart
      get :logs, controller: "logs", action: :show, as: :logs
      get :follow, controller: "logs", action: :follow, as: :follow
    end
  end
end
