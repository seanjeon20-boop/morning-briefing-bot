# frozen_string_literal: true

require "httparty"

class MarketDataFetcher
  YAHOO_FINANCE_API = "https://query1.finance.yahoo.com/v8/finance/chart"

  # Major indices
  INDICES = {
    "S&P 500" => "^GSPC",
    "NASDAQ" => "^IXIC",
    "DOW" => "^DJI",
    "VIX" => "^VIX",
    "Russell 2000" => "^RUT"
  }.freeze

  # Sector ETFs for tracking sector performance
  SECTOR_ETFS = {
    "Technology" => "XLK",
    "Healthcare" => "XLV",
    "Financials" => "XLF",
    "Consumer Discretionary" => "XLY",
    "Communication Services" => "XLC",
    "Industrials" => "XLI",
    "Consumer Staples" => "XLP",
    "Energy" => "XLE",
    "Utilities" => "XLU",
    "Real Estate" => "XLRE",
    "Materials" => "XLB"
  }.freeze

  def initialize
    @headers = {
      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    }
  end

  # Fetch all market data
  # @return [Hash] Market data including indices and sectors
  def fetch_all
    {
      indices: fetch_indices,
      sectors: fetch_sectors,
      hot_sectors: calculate_hot_sectors,
      fetched_at: Time.current
    }
  end

  # Fetch major indices data
  # @return [Array<Hash>] Array of index data
  def fetch_indices
    INDICES.map do |name, symbol|
      data = fetch_quote(symbol)
      next nil unless data

      {
        name: name,
        symbol: symbol,
        price: data[:price],
        change: data[:change],
        change_percent: data[:change_percent],
        direction: data[:change] >= 0 ? :up : :down
      }
    end.compact
  end

  # Fetch sector ETF data
  # @return [Array<Hash>] Array of sector data sorted by performance
  def fetch_sectors
    sectors = SECTOR_ETFS.map do |name, symbol|
      data = fetch_quote(symbol)
      next nil unless data

      {
        name: name,
        symbol: symbol,
        price: data[:price],
        change: data[:change],
        change_percent: data[:change_percent],
        direction: data[:change] >= 0 ? :up : :down
      }
    end.compact

    # Sort by change percent (best performers first)
    sectors.sort_by { |s| -s[:change_percent] }
  end

  # Get the hottest and coldest sectors
  # @return [Hash] Hot and cold sectors
  def calculate_hot_sectors
    sectors = fetch_sectors
    return { hot: [], cold: [] } if sectors.empty?

    {
      hot: sectors.first(3).map { |s| s[:name] },
      cold: sectors.last(3).reverse.map { |s| s[:name] }
    }
  end

  # Get market summary text for briefing
  # @return [String] Formatted market summary
  def market_summary_text
    data = fetch_all
    return "시장 데이터를 가져올 수 없습니다." if data[:indices].empty?

    lines = [ "📊 시장 현황" ]

    # Indices
    data[:indices].each do |index|
      emoji = index[:direction] == :up ? "🟢" : "🔴"
      sign = index[:change] >= 0 ? "+" : ""
      lines << "#{emoji} #{index[:name]}: #{format_number(index[:price])} (#{sign}#{index[:change_percent].round(2)}%)"
    end

    # Hot sectors
    if data[:hot_sectors][:hot].any?
      lines << ""
      lines << "🔥 핫 섹터: #{data[:hot_sectors][:hot].join(', ')}"
    end

    if data[:hot_sectors][:cold].any?
      lines << "❄️ 부진 섹터: #{data[:hot_sectors][:cold].join(', ')}"
    end

    lines.join("\n")
  end

  private

  def fetch_quote(symbol)
    url = "#{YAHOO_FINANCE_API}/#{symbol}"
    params = {
      interval: "1d",
      range: "2d"
    }

    response = HTTParty.get(url, query: params, headers: @headers)
    return nil unless response.success?

    parse_quote_response(response.parsed_response)
  rescue StandardError => e
    Rails.logger.error "Market data fetch error for #{symbol}: #{e.message}"
    nil
  end

  def parse_quote_response(data)
    result = data.dig("chart", "result", 0)
    return nil unless result

    meta = result["meta"]
    return nil unless meta

    current_price = meta["regularMarketPrice"]
    previous_close = meta["chartPreviousClose"] || meta["previousClose"]

    return nil unless current_price && previous_close

    change = current_price - previous_close
    change_percent = (change / previous_close) * 100

    {
      price: current_price,
      change: change,
      change_percent: change_percent
    }
  end

  def format_number(number)
    return "N/A" unless number

    if number >= 1000
      number.round(2).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    else
      number.round(2).to_s
    end
  end
end
