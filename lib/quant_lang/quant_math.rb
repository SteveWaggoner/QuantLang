#!ruby

#https://stackoverflow.com/questions/20538670/how-to-extract-the-sign-of-an-integer-in-ruby
class Numeric
  def sign
    if self > 0
        1
    elsif zero?
        0
    else
        -1
    end
  end
end


#https://stackoverflow.com/questions/488670/calculate-exponential-moving-average-in-python
def ema(s, n)
    ema = []
    j = 1

    #get n sma first and calculate the next n period ema
    sma = s.slice(0,n).reduce(0, :+) / n
    multiplier = 2 / (1 + n).to_f
    ema << sma.round(3)

    #EMA(current) = ( (Price(current) - EMA(prev) ) x Multiplier) + EMA(prev)
    ema << (( (s[n] - sma) * multiplier) + sma).round(3)

    #now calculate the rest of the values
    for ix in n+1..s.length-1
        i = s[ix]
        tmp = ( (i - ema[j]) * multiplier) + ema[j]
        j = j + 1
        ema << tmp.round(3)
    end
    return ema
end


def mean(x)
    total=0.0
    x.each {|v| total+=v }
    return total / x.size
end

#https://www.sciencebuddies.org/science-fair-projects/science-fair/variance-and-standard-deviation
def variance(x)
    mean_x = mean(x)
    sum_x2 = 0.0
    x.each {|v| sum_x2 += v*v }
    return (sum_x2 / x.size) - (mean_x*mean_x)
end

#http://ci.columbia.edu/ci/premba_test/c0331/s7/s7_5.html
def covariance(x,y)
    mean_x = mean(x)
    mean_y = mean(y)
    if x.size!=y.size
        raise "datasets are different sizes: #{x.size} != #{y.size}"
    end
    if x.size < 2
        raise "dataset is less than 2"
    end
    sum_xy = 0.0
    for i in 0...x.size
        sum_xy += (x[i] - mean_x)*(y[i] - mean_y)
    end
    return sum_xy / (x.size-1)
end


def stdev(x)
    mean_x = mean(x)
    sum_x=0.0
    x.each {|v| sum_x += (v - mean_x)**2}
    return (sum_x / (x.size-1))**0.5  #sample stdev
end


def correlation(x,y)
    cov_xy = covariance(x,y)
    sx = stdev(x)
    sy = stdev(y)
    return cov_xy/(sx*sy)
end

if __FILE__ == $0

    require "test/unit"

    class TestRunner < Test::Unit::TestCase

        def test_math
            test_numbers = [2,4,1,5,8]
            assert_equal(5.75, ema(test_numbers,3)[2] )
            assert_equal(4.0, mean(test_numbers) )
            assert_in_delta(2.7386, stdev(test_numbers), 0.0001 )
        end

    end

end

