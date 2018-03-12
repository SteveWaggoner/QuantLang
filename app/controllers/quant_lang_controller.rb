
require "./lib/quant_lang/quant_math"

class QuantLangController < ApplicationController

  def index
  end

  def edit
	render :edit
  end


  def compile(code)
	"[" + code + "] " + mean([2,4,1,5,8]).to_s
  end
  helper_method :compile


end
