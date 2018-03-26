
require "./lib/quant_lang/quant_lang"

class QuantLangController < ApplicationController

  def index
  end

  def edit
	render :edit
  end


  def compile(code)
      output = Parser.eval(code)
      return output
  end
  helper_method :compile


end
