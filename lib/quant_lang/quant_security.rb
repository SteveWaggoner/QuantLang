#!ruby

require_relative "quant_table"
require_relative "quant_math"

require "date"

class Balance < TableRow
    def initialize(dt)
        super()
        set_field("date", dt.to_s)
    end
end


class Security < TableRow

    def initialize
        super
        set_field("symbol", symbol)
    end

    def get_prices(dt, max)
        raise "not implemented in #{self.class.name}"
    end

    def get_holdings(dt, strategy_start_dt=nil)
        raise "not implemented in #{self.class.name}"
    end

    #helper methods
    def get_balance_table(start_dt, end_dt)

        ndays = (end_dt-start_dt)+1

        prices = get_prices(end_dt, ndays)
        if prices.first.date > start_dt
            first_price = get_prices(start_dt,5).last
            prices.unshift(first_price)
        end

        first_value = prices.first.value
        balances = []
        prices.each do |p|
            b = Balance.new(p.date)
            b.set_field("#{symbol} value", "$#{p.value.round(2)}")
            b.set_field("#{symbol} return", "#{(100.0*(p.value-first_value)/first_value).round(2)}%")

            get_holdings(p.date, start_dt).each do |stock,percent|
                b.set_field("#{stock.symbol} value", "$#{ (p.value * percent).round(2) }")
                b.set_field("#{stock.symbol} pct", "#{ (100.0 * percent).round(2) }%")
            end
            balances << b
        end
        return balances
    end

    def avg_price(dt, ndays, strategy_start_dt=nil)

        strategy_start_ndays = ndays
        if strategy_start_dt
            strategy_start_ndays = (dt - strategy_start_dt) + 1
        end

        if strategy_start_ndays > ndays
            prices = get_prices(dt, strategy_start_ndays).last(ndays)

        elsif ndays == 1 and self.is_a? Stock
            prices = get_prices(dt, 5).last(1) #if what avg_price for weekend..return previous workday
        else
            prices = get_prices(dt, ndays)
        end

        if prices.size != 0
            return prices.map{|p|p.value}.sum / prices.size
        else
            return nil
        end
    end

    def get_value(dt)

        if symbol == :CASH
            return 1
        end
        price = get_prices(dt,5).last
        if price == nil
            raise "cannot figure out price for #{self} for #{dt}"
        end
        price.value
    end

    def get_values(dt, ndays)
        get_prices(dt, ndays).map {|p| p.value}
    end

    def get_roi(from_dt, to_dt)

        ndays = to_dt-from_dt+1

        prices = get_prices(to_dt, ndays)
        cost  = prices.first.value
        value = prices.last.value

        if cost == nil
            raise "failed to get value from #{from_dt} for #{self}"
        end
        if value == nil
            raise "failed to get value from #{to_dt} for #{self}"
        end

        gain  = value - cost
        roi_percent =  (100.0 * gain / cost)
        return roi_percent
    end

    def print_roi(dt1, dt2=nil)

        if dt2 == nil
            from_dt = dt1-365
            to_dt = dt1
        else
            from_dt = dt1
            to_dt = dt2
        end

        ndays = to_dt-from_dt+1
        prices = get_prices(to_dt, ndays)
        cost  = prices.first
        value =  prices.last

        roi = get_roi(from_dt, to_dt)
        puts "#{self}: #{cost} --> #{value} (#{roi.round(4)}%)"
    end

    #https://www.investopedia.com/articles/investing/092115/alpha-and-beta-beginners.asp
    def get_alpha(from_dt, to_dt, market_stock)
        alpha = get_roi(from_dt, to_dt) - market_stock.get_roi(from_dt, to_dt)
        return alpha
    end

    def get_beta(from_dt, to_dt, market_stock)

        investment_returns = []
        market_returns = []

        dt = from_dt
        while dt <= to_dt

            v = get_value(dt)
            if v == nil
                raise "#{self} #{from_dt} #{to_dt} #{market_stock}"
            end

            investment_returns << get_value(dt)
            market_returns << market_stock.get_value(dt)
            dt += 1
        end

        beta = covariance(investment_returns, market_returns) / variance(market_returns)
        return beta
    end

    def symbol
        to_s
    end
    def inspect
        to_s
    end
end



