#!ruby

require_relative "quant_table"
require_relative "quant_math"
require_relative "quant_security"

require "date"
require "csv"
require "rbtree"


class Price
    attr_reader :date, :value

    def initialize(date, value)
        @date = date
        @value = value
    end

    def to_s
        "#{@date} $#{@value.round(2)}"
    end

    def inspect
        to_s
    end
end

class StockProfile
    attr_reader :name, :sector, :industry, :num_employees

    def initialize(file)
        n=0
        File.foreach(file) do |line|
            if n==0
                @name = line.strip
            end
            if n==5
                @sector = line.partition(': ').last.strip
            end
            if n==6
                @industry = line.partition(': ').last.strip
            end
            if n==7
                @num_employees = line.partition(': ').last.strip.delete(',').to_i
            end
            n += 1
        end
    end

    def to_s
        "#{name} sector:#{sector} industry:#{industry}"
    end
end

class StockStats

    def parseNum(text)
        if text.end_with? "%"
            val = (text.to_f / 100).round(6)
        elsif text.end_with? "B"
            val = (text.to_f * 1000000000).round
        elsif text.end_with? "M"
            val =(text.to_f * 1000000).round
        else
            val =text.to_f
        end
        return val
    end

    def remove_footnote(text)
        parts = text.split(" ")
        if parts.last.size==1 and parts.last.to_i > 0
            parts.pop
            return parts.join(' ')
        else
            return text
        end
    end

    def initialize(file)

        @stats = Hash.new
        File.foreach(file) do |line|
            parts = line.strip.split("\t")
            if parts.size==2
                @stats[remove_footnote(parts[0])] = [parts[1], parseNum(parts[1])]
            end
        end

    end

    def get(metric)
        if @stats.has_key? metric
            @stats[metric].last
        end
    end

    def eps
        get("Diluted EPS (ttm)")
    end

    def shares
        get("Shares Outstanding")
    end

    def beta
        get("Beta")
    end

    def to_s
        "#{self.class.name} #{@stats}"
    end
end


class Stock < Security
    attr_reader :symbol, :prices, :type, :commission, :profile, :stats, :market

    def initialize(symbol,type,commission,market)
        @symbol = symbol
        @type = type
        @commission = commission
        @prices = RBTree.new
        @market = market
        super()
    end

    def get_holdings(dt, strategy_start_dt=nil)
        return { self => 1 }
    end

    def read_prices(file)
        prices = CSV.read(file, headers:true)
        prices.each do |row|
            if row['Date'].include? '/'
                dt = DateTime.strptime(row['Date'], '%m/%d/%Y').to_date
            else
                dt = DateTime.strptime(row['Date'], '%Y-%m-%d').to_date
            end
            #@prices[dt] = Price.new(dt, row['Adj Close'].to_f)
            @prices[dt] = Price.new(dt, row['Close'].to_f)
        end
    end

    def read_profile(file)
        if File.file?(file)
            @profile = StockProfile.new(file)
        end
    end
    def read_stats(file)
        if File.file?(file)
            @stats = StockStats.new(file)
        end
    end

    def get_current_or_earlier_price(dt)
        if @symbol == :CASH
            return Price.new(dt,1)
        end
        day_price_it = @prices.upper_bound(dt) #this date or eariler
        if day_price_it
            @prices[day_price_it.first]
        else
            raise "Cannot find #{@symbol} price for #{dt}"
        end
    end

    def get_current_or_later_price(dt)
        if @symbol == :CASH
            return Price(dt,1)
        end
        day_price_it = @prices.lower_bound(dt) #this date or later
        if day_price_it
            @prices[day_price_it.first]
        else
            raise "Cannot find #{@symbol} price for #{dt}"
        end
    end
    def round_purchase(qty)
        if @type == :STOCK
            qty.round(0)
        else
            qty.round(4)
        end
    end

    def to_s
        "#{@symbol}"
    end


    def get_prices(dt, ndays)

        if symbol == :CASH
            return [ Price.new(dt,1) ]
        end


        prices = []
        if ndays > 0
            itlo = @prices.lower_bound(dt - ndays + 1)
            itup = @prices.upper_bound(dt)

            if itlo == nil or itup == nil
                return []
            end

            @prices.bound(itlo.first, itup.first) do |k, v|
                #prices.unshift v.adj_close  #newer prices first..older prices later
                prices << v  #newer prices later
            end
        end
        return prices
    end

end

class Market
    attr_reader :stocks

    def initialize()
        @stocks = Hash.new
        @stocks[:CASH] = Stock.new(:CASH,:CASH,0,self)
    end

    def add_all
        symbols = Dir[ './prices/*.csv' ].select{ |f| File.file? f }.map{|f| File.basename(f,'.csv')}.select {|s| not @stocks.has_key? s}
        symbols.each {|s| add_stock(s, :STOCK_OR_MUTUAL, 10)}
    end


    def full_path(rel_path)
	File.expand_path(rel_path, File.dirname(__FILE__))
    end

    def add_stock(symbol,type,commission)
        @stocks[symbol] = Stock.new(symbol,type,commission,self)
        @stocks[symbol].read_prices(full_path("prices/#{symbol}.csv"))
        @stocks[symbol].read_profile(full_path("profiles/#{symbol}.txt"))
        @stocks[symbol].read_stats(full_path("stats/#{symbol}.txt"))
    end

end


