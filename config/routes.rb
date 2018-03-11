Rails.application.routes.draw do
  root 'hello_world#index'
  get 'hello_world/index'


  match '/edit' => 'quant_lang#edit', via: :get
  match '/edit' => 'quant_lang#edit', via: :post

end
