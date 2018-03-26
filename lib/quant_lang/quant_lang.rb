#!ruby
# coding: utf-8

require 'treetop'
require 'chronic'

require './quant_strategy'
require './quant_market'

class ValueNode < Treetop::Runtime::SyntaxNode
end


class IntegerNode < ValueNode

    def eval(program)
        return self.text_value.to_i
    end

    def value
        self.text_value.to_i
    end

    def to_sx
        inspect
    end

    def inspectx
        " IntegerNode: "+self.text_value.to_i.to_s
    end

end

class PercentNode < ValueNode
    def value
        return self.text_value.to_i / 100.0
    end
end

class FloatNode < ValueNode

    def eval(program)
        value
    end

    def value
        return self.text_value.to_f
    end
end

module TextNumberNode
    def value
        case text_value
            when "zero"  then 0
            when "one"   then 1
            when "two"   then 2
            when "three" then 3
            when "four"  then 4
            when "five"  then 5
        end
    end
end


class FilterNode < Treetop::Runtime::SyntaxNode


    def is_biggest_attribute_best(attribute)
        case attribute
            when "market-cap" then true
            when "growth","return" then true
            when "pe-ratio" then false
            when "price" then false
            when "risk" then false
            when "beta" then false
            when "eps" then true
            when "shares" then false
            else raise "not sure about #{attribute}"
        end
    end


    def stock_attribute(stock, attribute, timespan)
        if timespan
            dt = timespan.end_date
            ndays = (timespan.end_date - timespan.start_date + 1).to_i

#puts "ndays=#{ndays} end=#{timespan.end_date} start=#{timespan.start_date}"

            ts_label = "#{timespan.text_value} "
        else
            dt = Chronic.parse("today").to_date
            ndays = 1
            ts_label = ""
        end
        case attribute
            when "market-cap" then
                    if stock.stats
                        marketcap = stock.avg_price(dt, ndays) * stock.stats.shares

                        if marketcap>1000000000
                            stock.set_field("marketcap", "$#{(marketcap/1000000000).round(1)}B")
                        else
                            stock.set_field("marketcap", "$#{(marketcap/1000000).round(1)}M")
                        end
                        return marketcap
                    else
                        stock.set_field("marketcap", "")
                        return 0
                    end


            when "growth", "return" then

                    if timespan
                        start_date = timespan.start_date
                        end_date = timespan.end_date
                    else
                        start_price = dt-365
                        end_price = dt
                    end

                    start_price = stock.avg_price(start_date,1)
                    end_price = stock.avg_price(end_date, 1, start_date)

                    if start_price == nil
                        puts "#{stock} #{start_date} #{start_price}"
                        raise "Boom"
                    end


                    stock.set_field("#{start_date} price", "$#{start_price.round(2)}")
                    stock.set_field("#{end_date} price",   "$#{end_price.round(2)}")


                    ts_label = "#{start_date} to #{end_date} "

                    if end_price and start_price
                        growth = ( (end_price-start_price) / start_price ).round(6)
                        stock.set_field("#{ts_label}growth", "#{(growth*100.0).round(2)}%")
                    else
                        growth = -1.0/0
                        stock.set_field("#{ts_label}growth", "")
                    end
                    return growth


            when "pe-ratio" then

                    price = stock.avg_price(dt, ndays)
                    if price and stock.stats and stock.stats.eps > 0
                        pe = price / stock.stats.eps
                        stock.set_field("pe ratio", "#{pe.round(4)}")
                    else
                        pe = 1.0/0  #pe ratio is positive infinity
                        stock.set_field("pe ratio", "")
                    end
                    return pe


            when "price" then

                    price = stock.avg_price(dt, ndays)
                    if price
                        stock.set_field("#{ts_label}price", "$#{price.round(2)}")
                    else
                        stock.set_field("#{ts_label}price", "")
                        price = 1.0/0
                    end
                    return price

            when "risk", "beta" then

                    if timespan
                        start_date = timespan.start_date
                        end_date = timespan.end_date
                    else
                        start_date = dt-365
                        end_date = dt
                    end

                    sp500 = stock.market.stocks["VFINX"]
                    beta = stock.get_beta(start_date, end_date, sp500)

                    stock.set_field("beta", "#{beta.round(3)}")
                    return beta

            when "eps" then
                    if stock.stats
                        stock.set_field("eps", "$#{stock.stats.eps.round(2)}")
                        return stock.stats.eps
                    else
                        stock.set_field("eps", "")
                        return -1.0/0
                    end

            when "shares" then
                    if stock.stats
                        stock.set_field("shares", "#{(stock.stats.shares/1000000.0).round(1)}M")
                        return stock.stats.shares
                    else
                        stock.set_field("shares", "")
                        return -1.0/0
                    end


            else raise "Unknown attribute: #{attribute}"
        end
    end

end


class FilterValueNode < FilterNode
    def eval(program,array=nil)

        if array == nil
            array = program.market.stocks.map { |symbol,stock| stock }
        end

        if timespan
            start_date = timespan.start_date
            end_date = timespan.end_date
        else
            start_date = nil
            end_date = nil
        end

        #sort
        array.sort! do |a,b|
            stock_attribute(a,variable,timespan) <=> stock_attribute(b,variable,timespan)
        end
        if array.size==1
            stock_attribute(array[0],variable,timespan)
        end

        if is_biggest_attribute_best(variable)
            array.reverse!
        end

        #filter
        case type
            when "top"  then array = array.take(amount)
            when "most" then array = array.take(amount)
            when "best" then array = array.take(amount)
            when "least" then array = array.take(amount)
            when "lowest" then array = array.take(amount)
            when "greater-than" then array = array.select {|stock| stock_attribute(stock,variable,timespan) > amount}
            when "less-than" then array = array.select {|stock| stock_attribute(stock,variable,timespan) < amount}

            when "dump" then array.each {|stock| print_table(stock.get_balance_table(timespan.start_date, timespan.end_date)) }

            else raise "Unsupported type: #{type}"
        end


    end

    def type
        self.elements[0].text_value
    end

    def amount
        if elements[1].empty?
            1
        else
            elements[1].elements[1].value
        end
    end

    def variable
        elements[3].text_value
    end

    def timespan
        if not elements[4].empty?
            elements[4].elements[1]
        end
    end

    def start_end_dates
        if timespan
            return timespan.start_end_dates
        else
            return [Chronic.parse("365 days ago").to_date, Chronic.parse("today").to_date]
        end
    end

end


class FilterAttributeNode < FilterNode
    def eval(program, array=nil)

        aka = { "tech" => "Technology", "biotech" => "Biotechnology" }
        value = ( aka[attrib1] || attrib1 ).downcase

        list = []

        if array == nil
            array = program.market.stocks.map { |symbol,stock| stock }
        end

        array.each do |stock|
            if stock.profile
                case attrib2
                    when "sector"   then match = stock.profile.sector.casecmp(value)==0
                                         stock.set_field("sector", stock.profile.sector)

                    when "industry" then match = stock.profile.industry.casecmp(value)==0
                                         stock.set_field("industry", stock.profile.industry)

                    when "stocks"   then match = (stock.profile.industry.downcase.include?(value) || stock.profile.sector.downcase.include?(value) )
                                         stock.set_field("sector", stock.profile.sector)
                                         stock.set_field("industry", stock.profile.industry)

                    else raise "unsupported attrib2: #{attrib2}"
                end
                if match or attrib1=="all"
                    list << stock
                end
            end
        end
        return list
    end

    def attrib1
        elements[0].text_value
    end
    def attrib2
        elements[2].text_value
    end

    def to_s
        " FilterAttributeNode: #{attrib1} #{attrib2}"
    end
    def inspect
        to_s
    end
end


class EvalNode < Treetop::Runtime::SyntaxNode
end

class IdNode < EvalNode

    def eval(program)
        if program.variables.has_key? variable_name
            program.variables[variable_name]
        elsif program.market.stocks.has_key? variable_name
            program.market.stocks[variable_name]
        elsif variable_name == "CASH"
            program.market.stocks[:CASH]
        else
            raise "Variable not found: "+variable_name
        end
    end

    def variable_name
        self.text_value
    end

    def inspect
        " IdNode: "+variable_name
    end

end

class CommandNode < EvalNode
end

class AssignmentNode < CommandNode

    def eval(program)

        val = expression.eval(program)
        self.filter_pipes.each do |pipe|
            val = pipe.eval(program,val)
        end
        program.variables[variable.variable_name] = val
    end


    def variable
        self.elements[0]
    end

    def expression
        self.elements[4]
    end

    def filter_pipes
        self.elements[5].elements.map{|x| x.elements[1].filter if x.elements[1].kind_of? FilterPipeNode}.compact
    end

end

class PrintNode < CommandNode

    def eval(program)
        val = expression.eval(program)
        self.filter_pipes.each do |pipe|
            val = pipe.eval(program,val)
        end

        if val.kind_of? Array and val.size>0 and val[0].kind_of? Security
            print_table(val)
        else
            puts val.to_s
        end
    end

    def expression
        self.elements[2]
    end

    def filter_pipes
        self.elements[3].elements.map{|x| x.elements[1].filter if x.elements[1].kind_of? FilterPipeNode}.compact
    end
end


class ObjectNode < EvalNode
    def classname
        self.elements[0].text_value
    end
    def params
        if self.elements[3] == nil
            nil
        else
            self.elements[3].value
        end
    end

    def eval(program)
        if params
            param_vals = params.eval(program)
        else
            param_vals = []
        end

        if program.factories.has_key? classname
            program.factories[classname].create(param_vals)
        else
            raise "Class not found: "+classname
        end
    end

    def to_sx
        inspect
    end

    def inspectx
        " ObjectNode: "+classname+"("+params.to_s+")"
    end

end

class ParamsNode < EvalNode
    def eval(program)
        arr = Array.new
        arr << self.elements[0].eval(program)
        if not self.elements[1].empty?
            more_cnt = self.elements[1].elements.size
            for n in 0...more_cnt
                arr << self.elements[1].elements[n].elements[3].eval(program)
            end
        end

        ordinal_values = []
        named_values = {}
        arr.each{|p| if p.kind_of?(Array) then ordinal_values << nil else ordinal_values << p end}
        arr.select{|p|p.kind_of? Array}.each{|p| named_values[p[0]] = p[1]}
        return [ordinal_values,named_values]
    end

    def to_sx
        inspect
    end

    def inspectx
        " ParamsNode: "+eval(nil).to_s
    end
end

class NamedParamNode < EvalNode
    def eval(program)
        [ elements[0], elements[4] ]
    end

    def value
        [ elements[0].text_value, elements[4].value ]
    end

    def inspectx
        " NamedParamNode: "+elements[0].text_value+"=>"+elements[4].to_s
    end
end

class ArrayNode < EvalNode

    def eval(program)
        arr = []
        arr << self.elements[2].eval(program)
        if not self.elements[4].empty?
            more_cnt = self.elements[4].elements.size
            for n in 0...more_cnt
                arr << self.elements[4].elements[n].elements[2].eval(program)
            end
        end

        arr2 = []
        arr.each do |e|
        if e.kind_of?(Array)
               e.each do |e2|
                   arr2 << e2
               end
           else
                arr2 << e
           end
        end


        return arr2
    end

end

class TimespanNode < Treetop::Runtime::SyntaxNode

   def type
        return elements[0].text_value
   end
   def length
        if not self.elements[1].empty?
           len = self.elements[1].elements[1].text_value
           case len
             when "zero" then return 0
             when "one"  then return 1
             when "two"  then return 2
             else        return len.to_i
           end
        else
           return 1
        end
   end


   def units
        if self.elements[3].elements[0].is_a? MonthsNode
            return "specific-month"
        end
        if self.elements[3].elements[0].is_a? QuartersNode
            return "specific-quarter"
        end
        return self.elements[3].elements[0].text_value
   end

   def units2
        return self.elements[3].elements[0].text_value
   end

   def start_end_dates
        case type
            when "last" then
                yesterday = Date.today - 1
                month = yesterday.month
                year  = yesterday.year
                case units
                    when "year" then
                        end_date = Chronic.parse("jan 1 #{year}").to_date
                        start_date = Chronic.parse("jan 1 #{year - length}").to_date
                    when "quarter" then
                        quarter = ((month-1) / 3).floor
                        first_month = ["january", "april", "july", "october"]
                        end_date = Chronic.parse("#{first_month[quarter]} 1, #{year}").to_date
                        if quarter == 0
                            start_date = Chronic.parse("#{first_month[4-length]} 1, #{year-1}").to_date
                        else
                            start_date = Chronic.parse("#{first_month[quarter-length]} 1, #{year}").to_date
                        end
                    when "month" then
                        end_date = Chronic.parse("#{month}/1/#{year}").to_date
                        if month == 1
                            start_date = Chronic.parse("#{13 - length}/1/#{year-1}").to_date
                        else
                            start_date = Chronic.parse("#{month-length}/1/#{year}").to_date
                        end

                    when "day" then
                        end_date = yesterday
                        start_date = end_date - length

                    when "specific-quarter" then
                        qstartmonth = {"q1"=>"january", "q2"=>"april", "q3"=>"july","q4"=>"october"}
                        start_date = Chronic.parse("#{qstartmonth[units2]} 1, #{year}").to_date
                        if yesterday < (start_date >> 3)
                            start_date = Chronic.parse("#{qstartmonth[units2]} 1, #{year-1}").to_date
                        end
                        end_date = (start_date >> 3)

                    when "specific-month" then
                        start_date = Chronic.parse("#{units2} 1, #{year}").to_date
                        if DateTime.now < (start_date >> 1)
                            start_date = Chronic.parse("#{units2} 1, #{year-1}").to_date
                        end
                        end_date = (start_date >> 1)

                    else
                        raise "not supported: #{units}"
                end

                return [start_date, end_date]

            when "current" then
                raise "not supported"
        end
   end

   def start_date
        @start_date ||= start_end_dates[0]   #cache return value
   end
   def end_date
        @end_date ||= start_end_dates[1]     #cache return value
   end

end

module MonthsNode
end
module QuartersNode
end

class FilterPipeNode < Treetop::Runtime::SyntaxNode
    def filter
        return self.elements[2] #FilterValueNode or FilterAttributeNode
    end
end



class MACD_Factory

    def create(param_values)

         a = ( param_values[1]['a'] || param_values[0][0] )
         b = ( param_values[1]['b'] || param_values[0][1] )
         c = ( param_values[1]['c'] || param_values[0][2] )

         MacdIndicator.new(a,b,c)
    end

end

class Momentum_Factory
    def create(param_values)
         ndays = ( param_values[1]['ndays'] || param_values[0][0] )
         MomentumIndicator.new(ndays)
    end
end

class AllIn_Factory
    def create(param_values)
         AllInIndicator.new
    end
end

class Strategy_Factory
    def initialize(market)
        @market = market
    end

    def create(param_values)

         if param_values[0].size != 4
            raise "expected 4 parameters for Strategy"
         end

         stock     = ( param_values[1]['stock']     || param_values[0][0] )
         indicator = ( param_values[1]['indicator'] || param_values[0][1] )
         percent_tolerance = ( param_values[1]['percent_tolerance'] || param_values[0][2] )
         min_cash_percent  = ( param_values[1]['min_cash_percent']  || param_values[0][3] )
         OptStrategy.new(@market, stock, indicator, percent_tolerance, min_cash_percent)
    end
end

class ProgramNode < Treetop::Runtime::SyntaxNode
    attr_reader :variables, :factories, :market

    def eval


        @market = Market.new
#        @market.add_stock('VFINX',:MUTUAL,0)
#        @market.add_stock('QQQ',:STOCK,6.95)
#        @market.add_stock('GE',:STOCK,6.95)
#        @market.add_stock('MERC',:STOCK,6.95)
#        @market.add_stock('AMSC',:STOCK,6.95)
#        @market.add_stock('PG',:STOCK,6.95)
        @market.add_stock('IBM',:STOCK,6.95)
#        @market.add_stock('CELG',:STOCK,6.95)
#        @market.add_stock('GOOG',:STOCK,0)
#        @market.add_all


        @variables = Hash.new
        @factories = Hash.new
        @factories["MACD"] = MACD_Factory.new
        @factories["Momentum"] = Momentum_Factory.new
        @factories["AllIn"] = AllIn_Factory.new
        @factories["Strategy"] = Strategy_Factory.new(@market)

        self.commands.each {|c| c.eval(self)}
    end

    def recursive_eval(node)
        while node.is_a? Treetop::Runtime::SyntaxNode
           node = node.eval(self)
        end
        return node
    end

    def commands
        return self.elements.map {|x| x if x.kind_of? AssignmentNode or x.kind_of? PrintNode}.compact
    end

end

def with_captured_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
end




class Parser

  Treetop.load('quant_lang.treetop')
  @@parser = QuantLangParser.new

  def self.parse(data)

    # Pass the data over to the parser instance
    tree = @@parser.parse(data)


    # If the AST is nil then there was an error during parsing
    # we need to report a simple error message to help the user
    if(tree.nil?)
      raise Exception, "Parse error at offset: #{@@parser.index}\n#{@@parser.failure_reason}"
    end

    return tree
  end

  def self.eval(data)

      str = with_captured_stdout { 
    
        tree = @@parser.parse(data)
        if(tree.nil?)
            puts "Parse error at offset: #{@@parser.index}\n#{@@parser.failure_reason}"
        else
            tree.eval
        end
    }
    return str

  end


end

if __FILE__ == $0

        output = Parser.eval(ARGV[0])
        puts output

end

