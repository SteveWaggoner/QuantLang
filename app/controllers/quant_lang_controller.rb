require "./lib/quant_lang/quant_lang"

class QuantLangController < ApplicationController

  def index
  end

  def edit
    render :edit
  end

  def evaluate_ql_code(code)
    output = Parser.evaluate(code)
    return output
  end

  helper_method :evaluate_ql_code

end
