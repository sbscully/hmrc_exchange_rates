require 'date'
require 'http'
require 'nokogiri'
require 'csv'

class ExchangeRates
  BASE_URL = 'http://www.hmrc.gov.uk/softwaredevelopers/rates/exrates-monthly-'.freeze
  MONTHS = (1..12).map { |n| n.to_s.rjust(2, '0') }.freeze

  attr_reader :files, :rows

  def initialize
    @files = []
  end

  def fetch!
    current_year = Date.today.year.to_s[-2..-1].to_i
    (15..current_year).each do |year|
      MONTHS.each do |month|
        url = "#{BASE_URL}#{month}#{year}.xml"
        response = HTTP.get(url)
        puts "#{response.status} :: #{url}"
        next unless response.status == 200

        File.write("data/20#{year}-#{month}.xml", response.body.to_s)
      end
    end
  end

  def parse!
    @rows = Dir.glob('data/**.xml').map do |pathname|
      parse_one(pathname)
    end
  end

  def convert!
    pivoted = rows.flatten.each_with_object({}) do |row, output|
      currency = row.slice(*%w(countryName countryCode currencyName currencyCode))
      output[currency] ||= {}
      output[currency][row['date']] = row['rateNew']
    end

    dates = pivoted.flat_map do |currency, rates|
      rates.keys
    end.uniq.sort_by { |date| date.split('/').reverse }

    data = pivoted.map do |currency, rates|
      currency.values_at(*%w(countryName countryCode currencyName currencyCode)) + dates.map do |date|
        rates[date]
      end
    end

    CSV.open('hmrc-exchange-rates.csv', 'wb') do |csv|
      csv << ([''] * 4) + dates
      data.sort_by { |row| row[1] }.each do |row|
        csv << row
      end
    end
  end

  private

  def parse_one(pathname)
    xml = Nokogiri::XML(File.read(pathname))

    month = xml.xpath('//exchangeRateMonthList/@Period').first.value
    month = month.split(' to ').last
    month = DateTime.strptime(month, '%d/%b/%Y')

    rates = xml.xpath('//exchangeRate')
    rates.map do |rate|
      parse_rate(rate).merge('date' => month.strftime('%d/%m/%Y'))
    end
  end

  def parse_rate(rate)
    rate.children.select { |node| node.class == Nokogiri::XML::Element }
        .map { |elem| [elem.name, elem.text] }.to_h
  end
end

exchange = ExchangeRates.new
exchange.fetch!
exchange.parse!
exchange.convert!
