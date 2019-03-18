require 'openssl'
require 'faraday'
require 'benchmark'
require 'concurrent'

OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

# Есть три типа эндпоинтов API
# Тип A:
#   - работает 1 секунду
#   - одновременно можно запускать не более трёх
# Тип B:
#   - работает 2 секунды
#   - одновременно можно запускать не более двух
# Тип C:
#   - работает 1 секунду
#   - одновременно можно запускать не более одного
#
def a(value)
  Faraday.get("https://localhost:9292/a?value=#{value}").body
end

def b(value)
  puts "https://localhost:9292/b?value=#{value}"
  Faraday.get("https://localhost:9292/b?value=#{value}").body
end

def c(value)
  Faraday.get("https://localhost:9292/c?value=#{value}").body
end

# Референсное решение, приведённое ниже работает правильно, занимает ~19.5 секунд
# Надо сделать в пределах 7 секунд

def collect_sorted(arr)
  arr.sort.join('-')
end

def promisify(pool, &block)
  Concurrent::Promises.future_on(pool, &block)
end
a_pool = Concurrent::FixedThreadPool.new 3
b_pool = Concurrent::FixedThreadPool.new 2
c_pool = Concurrent::FixedThreadPool.new 1

time = Benchmark.realtime do
  r1 = Concurrent::Promises.future do
    a11 = promisify(a_pool) { a(11) }
    a12 = promisify(a_pool) { a(12) }
    a13 = promisify(a_pool) { a(13) }
    b1 = promisify(b_pool) { b(1) }
    c1 = Concurrent::Promises.zip(a11, a12, a13, b1)
      .then do |a11, a12, a13, b1|
        ab1 = "#{collect_sorted([a11, a12, a13])}-#{b1}"
        puts "AB1 = #{ab1}"
        ab1
      end
      .then { |val| promisify(c_pool) { c(val) } }.flat(1)
      puts "C1 = #{c1.value!}"
    c1
  end.flat(1)

  r2 = Concurrent::Promises.future do
    a21 = promisify(a_pool) { a(21) }
    a22 = promisify(a_pool) { a(22) }
    a23 = promisify(a_pool) { a(23) }
    b2 = promisify(b_pool) { b(2) }
    c2 = Concurrent::Promises.zip(a21, a22, a23, b2)
      .then do |a21, a22, a23, b2|
        ab2 = "#{collect_sorted([a21, a22, a23])}-#{b2}"
        puts "AB2 = #{ab2}"
        ab2
      end
      .then { |val| promisify(c_pool) { c(val) } }.flat(1)
      puts "C2 = #{c2.value!}"
    c2
  end.flat(1)

  r3 = Concurrent::Promises.future do
    a31 = promisify(a_pool) { a(31) }
    a32 = promisify(a_pool) { a(32) }
    a33 = promisify(a_pool) { a(33) }
    b3 = promisify(b_pool) { b(3) }
    c3 = Concurrent::Promises.zip(a31, a32, a33, b3)
      .then do |a31, a32, a33, b3|
        ab3 = "#{collect_sorted([a31, a32, a33])}-#{b3}"
        puts "AB3 = #{ab3}"
        ab3
      end
      .then { |val| promisify(c_pool) { c(val) } }.flat(1)
      puts "C3 = #{c3.value!}"
    c3
  end.flat(1)

  result = Concurrent::Promises.zip(r1, r2, r3)
    .then do |r1, r2, r3|
      collect_sorted([r1, r2, r3])
    end
    .then { |val| a(val)}

    raise "Incorrect response" if "0bbe9ecf251ef4131dd43e1600742cfb" != result.value!
    puts "RESULT = #{result.value!}"
end
raise "Time limit reached (more then 7s)" if time > 7
