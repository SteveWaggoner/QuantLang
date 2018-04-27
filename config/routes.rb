Rails.application.routes.draw do
  root 'quant_lang#edit'

  match '/edit' => 'quant_lang#edit', via: :get
  match '/edit' => 'quant_lang#edit', via: :post

  match '/QuantLang/edit' => 'quant_lang#edit', via: :get
  match '/QuantLang/edit' => 'quant_lang#edit', via: :post


end
