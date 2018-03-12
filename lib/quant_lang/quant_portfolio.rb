#!ruby

require "./quant_table"
require "./quant_security"


class Transaction < TableRow
    attr_reader :stock, :dt, :quantity, :price, :type, :seq

    @@seq = 0
    def initialize(stock, dt, quantity, price, type = nil)
        super()
        if price.is_a? Price
           raise "Price should be a value."
        end

        @stock = stock
        @dt = dt
        @quantity = quantity
        @price = price
        @type = type

        @@seq += 1
        @seq = @@seq


        set_field("date", dt.to_s)
        if stock.symbol == :CASH
            if @quantity > 0
                set_field("type", "DEPOSIT")
                set_field("value",  "$#{@quantity.round(2)}")
            else
                set_field("type", "PAY")
                set_field("value",  "$#{(-@quantity).round(2)}")
            end
        else
            if @quantity > 0
                set_field("type",  "PURCHASE")
                set_field("shares",   "#{(@quantity).round(4)}")
                set_field("stock", "#{@stock.symbol}")
                set_field("price", "$#{price.round(2)}")
                set_field("value", "$#{(price*@quantity).round(2)}")
            else
                set_field("type",  "SELL")
                set_field("shares",   "#{@quantity.round(4)}")
                set_field("price", "$#{price.round(2)}")
                set_field("value", "$#{(price*@quantity).round(2)}")
            end
        end
        set_field("comment", type.to_s)
    end

end


class Portfolio < Security
    attr_reader :market

    def initialize(market,percent_tolerance,min_cash_percent)
        @market = market
        @percent_tolerance = percent_tolerance
        @min_cash_percent = min_cash_percent

        @transactions = Array.new
        @comments = Hash.new
        super()
    end

    def add_comment(dt,stock,comment)
        @comments["#{dt}#{stock}"] = comment
    end
    def get_comment(dt,stock)
        @comments["#{dt}#{stock}"]
    end

    def deposit(dt, symbol, amt)
        cash_or_stock  = @market.stocks[symbol]
        if symbol == :CASH
            price = 1
        else
            price = cash_or_stock.get_current_or_later_price(dt).value
        end
        @transactions << Transaction.new(cash_or_stock, dt, amt, price)
    end

    def trade(dt, symbol, quantity, price=nil)

        cash  = @market.stocks[:CASH]
        stock = @market.stocks[symbol]
        if stock == nil
            raise "Symbol not found: #{symbol}"
        end

        if price == nil
            price = stock.get_current_or_later_price(dt).value
        end

        cash_amt = get_quantity(cash, dt)
        stock_shares = get_quantity(stock, dt)

        quantity2 = stock.round_purchase(quantity) #stock must be whole number

        if quantity2 > 0
            if cash_amt < quantity2 * price
                raise "Not enough cash to purchase #{quantity2} of #{symbol} (need $#{(quantity2*price).round(2)} but have $#{cash_amt.round(2)})"
            end
        end
        if quantity2 < 0
            if stock_shares < -quantity2
                raise "Not enough stock to sell #{stock_shares.round(2)} shares of #{symbol} (need #{(-quantity).round(2)} shares but own #{stock_shares.round(2)} shares)"
            end
        end

        if quantity2.abs == 0
            puts "Not doing transaction since transaction quantity is zero. (want to #{quantity.round(4)} but rounded number is #{quantity2.round(4)})"
        elsif quantity2.abs * price < 2*stock.commission
            puts "Note doing transaction since commission is more than 50% of transaction (val=$#{(quantity2 * price).abs.round(2)} comm=#{stock.commission})"
        else
            @transactions << Transaction.new(stock, dt, quantity2, price,    :TRADE)
            @transactions << Transaction.new(cash,  dt,-quantity2*price, 1,  :TRADE)
            @transactions << Transaction.new(cash, dt, -stock.commission, 1, :COMMISSION)
        end
    end

    def get_quantity(stock, dt)
        qty = 0
        @transactions.each do |transaction|
            if transaction.dt <= dt and transaction.stock == stock
                qty = qty + transaction.quantity
            end
        end
        qty
    end

    def get_balances(dt)

        if @cached_balances_dt == dt and @cached_balances_trans_size == @transactions.size
            return @cached_balances
        end

        bal = Hash.new
        @transactions.each do |transaction|
            if transaction.dt <= dt
                prev = bal[transaction.stock]
                if prev == nil
                    bal[transaction.stock] = transaction.quantity
                else
                    bal[transaction.stock] = prev + transaction.quantity
                end
            end
        end

        bal_vals = Hash.new
        bal.each do |stock,amt|
            bal_vals[stock] = stock.get_current_or_earlier_price(dt).value * amt
        end

        @cached_balances_dt = dt
        @cached_balances_trans_size = @transactions.size
        @cached_balances = bal_vals

        return bal_vals
    end

    def get_value(dt)
        total = 0
        bal_vals = get_balances(dt)
        bal_vals.each do |stock,val|
            total = total + val
        end
        total
    end


    def get_prices(dt, ndays)
        values = []
        (0...ndays).each do |n|
            values << Price.new(dt-n,get_value(dt-n))
        end
        return values.reverse
    end

    def get_holdings(dt, strategy_start_dt=nil)

        balances = get_balances(dt)
        total_value = get_value(dt)
        holdings = Hash.new
        balances.each do |stock,val|
            pct = val / total_value
            add_holdings(dt, stock, pct, holdings)
        end
        holdings

    end

    def add_holdings(dt, stock, pct, holdings)
        sub_holdings = stock.get_holdings(dt)
        sub_holdings.each do |sub_stock,sub_pct|
            if holdings.has_key? sub_stock
                holdings[sub_stock] = holdings[sub_stock] + (sub_pct * pct)
            else
                holdings[sub_stock] = (sub_pct * pct)
            end
        end
    end


    def normalize_goals(goal_percents)
        new_goals = Hash.new
        total_pct = 0
        current_cash_pct = 0
        goal_percents.each do |stock,goal_pct|
            if stock != :CASH and stock.symbol != :CASH
                total_pct += goal_pct
            else
                current_cash_pct += goal_pct
            end
        end

        #if current have minimum cash than check cash level else goto minimum
        if @min_cash_percent < current_cash_pct
            cash_pct = current_cash_pct
        else
            cash_pct = @min_cash_percent
        end

        goal_percents.each do |stock,goal_pct|
            if stock != :CASH and stock.symbol != :CASH
                new_goals[stock] = ((goal_pct/total_pct)*(1-cash_pct)).round(4)
            end
        end

        new_goals[@market.stocks[:CASH]] = cash_pct

        return new_goals
    end

    def rebalance(dt, goal_percents)

        normalize_goal_pcts = normalize_goals(goal_percents)

#       print_diff(dt, normalize_goal_pcts, 'BEFORE BALANCE')

        total_value = get_value(dt)
        current_balances = get_balances(dt)

        current_balances.each do |stock,val|
            pct = val / total_value
            goal_pct = normalize_goal_pcts[stock]
            price = stock.get_current_or_earlier_price(dt).value

            if goal_pct == nil
                goal_pct = 0
            end
            #sells
            if pct > goal_pct + @percent_tolerance and stock.symbol != :CASH
                have_val = total_value * pct
                want_val = total_value * goal_pct
                sell_val = have_val - want_val
#               puts "Have #{(100*pct).round(1)}% of #{stock.symbol} but want #{100*goal_pct}% pct so sell it (current val is $#{val.round(2)} so let sell $#{sell_val.round(2)})"
                trade(dt, stock.symbol, -sell_val / price, price)
            end
        end
        normalize_goal_pcts.each do |stock,goal_pct|

            val = current_balances[stock]
            if val == nil
                val = 0
            end
            pct = val / total_value
            price = stock.get_current_or_earlier_price(dt).value

            #buys
            if pct < goal_pct - @percent_tolerance and stock.symbol != :CASH

                cashOnHand = get_balances(dt)[@market.stocks[:CASH]]

                have_val = total_value * pct
                want_val = total_value * goal_pct
                buy_val = want_val - have_val

#               puts "Have #{(100*pct).round(1)}% of #{stock.symbol} but want #{100*goal_pct}% so buy it (current val is $#{val.round(2)} so let buy $#{buy_val.round(2)})"
                if buy_val + 20 < cashOnHand
                    trade(dt, stock.symbol, buy_val / price, price)
                else
                    puts "  skipping trade since only have $#{cashOnHand.round(2)} cash on hand but need $#{buy_val}"
                end
            end
        end
#       print_diff(dt, normalize_goal_pcts, 'AFTER BALANCE')
    end

    def print_diff(dt, goal_percents, comment)
        pcts = Hash.new

        total_value = get_value(dt)
        balances = get_balances(dt)
        balances.each do |stock,val|
            pcts[stock] = val / total_value
        end

        goal_percents.each do |stock,goal_pct|
            if not pcts.has_key? stock
                pcts[stock] = 0
            end
        end


        puts '-------------------------------'
        puts "#{dt} #{comment}"
        puts '-------------------------------'
        pcts.each do |stock,pct|
            if goal_percents.has_key? stock
                goal_pct = goal_percents[stock]
            else
                goal_pct = 0
            end
            puts "#{stock} current=#{(pct*100).round(1)}% : goal=#{goal_pct*100}%"
        end
        puts '-------------------------------'

    end

    def print_transactions
        @transactions.sort_by! { |k| [k.dt, k.seq] }
        @transactions.each do |t|
            if t.stock.symbol != :CASH
                comment = get_comment(t.dt,t.stock)
                t.set_field("comment", comment)
            end
        end
        print_table(@transactions)
    end

end

if __FILE__ == $0

    require "test/unit"

    require "./quant_market"

    class TestRunner < Test::Unit::TestCase

        def test_portfolio

            market=Market.new
            market.add_all
            portfolio=Portfolio.new(market,0.01,0.01)

            portfolio.deposit(Date.parse("2017-01-01"), :CASH, 100)
            portfolio.print_transactions
            assert_equal(100, portfolio.get_value(Date.today))


            portfolio.trade(Date.parse("2017-01-05"), "GE", 1)
            portfolio.print_transactions

            print_table(portfolio.get_balance_table(Date.parse("2017-01-01"), Date.parse("2017-01-06")))

            assert_equal(90, portfolio.get_value(Date.parse("2017-01-05")))
            assert_equal(0, portfolio.get_roi(Date.parse("2017-01-01"), Date.parse("2017-01-04")))
            assert_equal(-10, portfolio.get_roi(Date.parse("2017-01-01"), Date.parse("2017-01-05")))
            assert_in_delta(-9.90, portfolio.get_roi(Date.parse("2017-01-01"),Date.parse("2017-01-06")),0.01)

        end

    end

end


