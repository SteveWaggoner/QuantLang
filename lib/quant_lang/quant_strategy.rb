#!ruby

require_relative "quant_table"
require_relative "quant_math"
require_relative "quant_security"
require_relative "quant_portfolio"

require "date"

def macd_histogram(prices, a, b, c)

    price_values = prices.map {|p| p.value}
    slow_ema = ema(price_values, a)
    fast_ema = ema(price_values, b)

    diff = []
    slow_ema.reverse.zip(fast_ema.reverse).each do |s,f|
        if f == nil
           break
        end
        diff << (s - f)
    end
    diff.reverse!

    signal = ema(diff, c)

    histogram = []
    diff.reverse.zip(signal.reverse).each do |d,s|
        if s == nil
           break
        end
        histogram << (d - s)
    end
    histogram.reverse!

    return histogram
end

def momentum_histogram(prices, delay)

    momentum = []
    for i in 0..(prices.length - 1 - delay)
        momentum << prices[i + delay].value - prices[i].value
    end
    return momentum

end



class Outlook
    attr_reader :dt, :stock, :indicator

    def initialize(dt, stock, indicator)
        @dt = dt
        @stock = stock
        @indicator = indicator
    end

    def get_strength(dt)
        prices = @stock.get_prices(dt, indicator.get_ndays)
        strength = @indicator.get_strength(prices)
        return strength
    end

    def strength
        return get_strength(@dt)
    end

    def to_s
        "#{dt} #{stock} #{indicator}"
    end

    def inspect
        to_s
    end

end



class Indicator
    def get_ndays
        raise "not implemented in #{self.class.name}"
    end
    def get_strength(prices)
        raise "not implemented in #{self.class.name}"
    end
    def inspect
        to_s
    end
end

class AllInIndicator < Indicator
    def get_ndays
        return 0 #don't need to know the price
    end
    def get_strength(prices)
        return 1 #BUY
    end
    def to_s
        "AllIn"
    end
end


class MacdIndicator < Indicator
    def initialize(a,b,c)
        @a = a
        @b = b
        @c = c
    end
    def get_ndays
        return 100 #for a good EMA use 100 days
    end
    def get_strength(prices)
        histogram = macd_histogram(prices, @a, @b, @c)
        strength = histogram.last
        return strength
    end
    def to_s
        "MACD(#{@a},#{@b},#{@c})"
    end
end


class MomentumIndicator < Indicator
    def initialize(delay)
        @delay = delay
    end
    def get_ndays
        @delay+10
    end
    def get_strength(prices)
        histogram = momentum_histogram(prices, @delay)
        strength = histogram.last
        return strength
    end
    def to_s
        "MO(#{@delay})"
    end
end


def modify_goals(holdings, outlook)

    buys = Hash.new
    sells = Hash.new

    new_goals = Hash.new

    #buy
    if outlook.strength > 0

        buy_holdings = outlook.stock.get_holdings(outlook.dt)

        total_buy_pct = 0
        buy_holdings.each do |buy_stock,buy_pct|
            if buy_stock.symbol != :CASH
                total_buy_pct += buy_pct
            end
        end

        buy_holdings.each do |buy_stock,buy_pct|
            if buy_stock.symbol != :CASH
                buys[buy_stock] = (buy_pct/total_buy_pct) * 0.9999  #hard limit of not buying more than 99.99% of cash on hand
            end
        end

    end


    #sell
    if outlook.strength < 0 and holdings.has_key?(outlook.stock)
        sells[outlook.stock] = 0
    end


    #hold
    total_pct = 0
    holdings.each do |stock,current_hold_pct|

        if stock.symbol != :CASH
            new_hold_pct = ( sells[stock] || current_hold_pct)
            if new_hold_pct > 0
                new_goals[stock] = new_hold_pct
                total_pct += new_hold_pct
            end
        end
    end


    buys.each do |stock, buy_pct|
        remaining_pct = ( 1-total_pct ).round(2)
        if remaining_pct > 0 and remaining_pct + total_pct <= 1
            new_goals[stock] = buy_pct
            total_pct += buy_pct
        end
    end

    if total_pct < 1
        new_goals[:CASH] = (new_goals[:CASH]||0) + (1-total_pct)
    end

    return new_goals
end


def apply_strategy(dt, strategy, portfolio)
    goals = strategy.get_goals(dt, portfolio)
    portfolio.rebalance(dt, goals)
end


class Strategy < Security

    def initialize(market,percent_tolerance,min_cash_percent)
        @market = market
        @percent_tolerance = percent_tolerance
        @min_cash_percent = min_cash_percent
        super()
    end

    def get_goals(dt, portfolio)
        raise "not implemented in #{self.class.name}"
    end

    def get_prices(dt,ndays)
        start_dt = dt-(ndays-1)
        portfolio = test_portfolio(start_dt, dt, +1000000, @percent_tolerance, @min_cash_percent)
        prices = portfolio.get_prices(dt, ndays)
        return prices
    end

    def get_holdings(dt, strategy_start_dt=nil)
        if not strategy_start_dt
            strategy_start_dt = dt
        end
        portfolio = test_portfolio(strategy_start_dt, dt, +1000000, @percent_tolerance, @min_cash_percent)
        return portfolio.get_holdings(dt)
    end

    def apply(dt, portfolio)
        goals = get_goals(dt, portfolio)
        portfolio.rebalance(dt, goals)
    end

    def test_portfolio(from_dt, to_dt, start_amt, percent_tolerance, min_cash_percent)
        portfolio = Portfolio.new(@market, percent_tolerance, min_cash_percent)
        portfolio.deposit(from_dt, :CASH, start_amt)
        dt = from_dt
        while dt <= to_dt
            apply(dt, portfolio)
            dt += 1
        end
        return portfolio
    end

end


class MixStrategy < Strategy

    def initialize(market, goals, percent_tolerance, min_cash_percent)
        super(market, percent_tolerance, min_cash_percent)
        @goals = goals
    end

    def add_goals(dt, stock, pct, holdings)
        sub_holdings = stock.get_holdings(dt)
        sub_holdings.each do |sub_stock,sub_pct|
            if holdings.has_key? sub_stock
                holdings[sub_stock] = holdings[sub_stock] + (sub_pct * pct)
            else
                holdings[sub_stock] = (sub_pct * pct)
            end
        end

    end


    def get_goals(dt, portfolio)
        new_goals = Hash.new
        @goals.each do |stock,pct|
            add_goals(dt, stock, pct, new_goals)
        end
        return new_goals
    end

    def to_s
        "Mix #{@goals}"
    end

end


class OptStrategy < Strategy

    def initialize(market, stock, indicator, percent_tolerance, min_cash_percent)
        @stock = stock
        @indicator = indicator
        super(market, percent_tolerance, min_cash_percent)
    end

    def get_strength(dt)
        "#{Outlook.new(dt, @stock, @indicator).strength.round(3)}"
    end

    def get_goals(dt, portfolio)
        outlook = Outlook.new(dt, @stock, @indicator)
        holdings = portfolio.get_holdings(dt)

        portfolio.add_comment(dt, outlook.stock, "#{@indicator} #{get_strength(dt)}")

        new_goals = modify_goals(holdings, outlook)
        return new_goals
    end

    def to_s
        "#{@stock} #{@indicator}"
    end

    def inspect
        to_s
    end

end


class Optimizer

    def initialize(market, stocks,indicators)
        @strategies = Array.new
        stocks.each do |s|
            indicators.each do |i|
                @strategies << OptStrategy.new(market,s,i)
            end
        end
    end

    def best_strategy
        @strategies[0]
    end

end

if __FILE__ == $0

    require "test/unit"

    require "./quant_market"

    class TestRunner < Test::Unit::TestCase

        def test_strat

            market = Market.new
            market.add_stock('VFINX',:MUTUAL,0)
            market.add_stock('QQQ',:STOCK, 0)
            market.add_stock('AMSC',:STOCK,6.95)
            market.add_stock('PG',:STOCK,6.95)
            market.add_stock('IBM',:STOCK,6.95)


            qqq = market.stocks["QQQ"]
            assert_equal("[2016-06-01 $110.35]",  qqq.get_prices(Date.parse("2016-06-01"),1).to_s)
            assert_equal([], qqq.get_prices(Date.parse("2016-06-04"),1))
            assert_equal([], qqq.get_prices(Date.parse("2016-06-05"),1))
            assert_equal("[2016-06-03 $110.06]", qqq.get_prices(Date.parse("2016-06-05"),5).last(1).to_s)

            all_qqq = OptStrategy.new(market, qqq, AllInIndicator.new,0.0001,0.02)

            assert_equal("[2016-06-01 $1000000.0]", all_qqq.get_prices(Date.parse("2016-06-01"),1).to_s)
            assert_equal("[2016-06-04 $1000000.0]", all_qqq.get_prices(Date.parse("2016-06-04"),1).to_s)
            assert_equal("[2016-06-05 $1000000.0]", all_qqq.get_prices(Date.parse("2016-06-05"),1).to_s)
            assert_equal("[2016-06-05 $997424.51]", all_qqq.get_prices(Date.parse("2016-06-05"),5).last(1).to_s)




            test_numbers = [2,4,1,5,8]
            assert_equal(5.75, ema(test_numbers,3)[2] )
            assert_equal(4.0, mean(test_numbers) )
            assert_in_delta(2.7386, stdev(test_numbers), 0.0001 )
        end

    end

end


