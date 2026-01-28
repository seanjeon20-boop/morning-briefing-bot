# frozen_string_literal: true

class Recommendation < ApplicationRecord
  validates :ticker, presence: true
  validates :action, presence: true, inclusion: { in: %w[BUY SELL HOLD WATCH] }
  validates :briefing_date, presence: true

  scope :this_week, -> { where(briefing_date: 1.week.ago.to_date..Date.current) }
  scope :this_month, -> { where(briefing_date: 1.month.ago.to_date..Date.current) }
  scope :buys, -> { where(action: "BUY") }
  scope :recent, -> { order(briefing_date: :desc) }

  # Update current price from market data
  def update_current_price!
    fetcher = MarketDataFetcher.new
    # Fetch current price (simplified - would need proper stock quote API)
    # For now, we'll update this manually or via a separate job
  end

  # Calculate return percentage
  def return_percentage
    return nil unless recommended_price && current_price && recommended_price > 0

    ((current_price - recommended_price) / recommended_price * 100).round(2)
  end

  # Check if target was hit
  def target_hit?
    return false unless current_price && target_price

    current_price >= target_price
  end

  # Check if stop loss was triggered
  def stop_loss_triggered?
    return false unless current_price && stop_loss

    current_price <= stop_loss
  end

  # Status based on performance
  def status
    return :target_hit if target_hit?
    return :stopped_out if stop_loss_triggered?

    pct = return_percentage
    return :unknown unless pct

    if pct > 0
      :winning
    elsif pct < 0
      :losing
    else
      :flat
    end
  end

  # Summary for display
  def summary
    return_pct = return_percentage
    return_str = return_pct ? "#{return_pct >= 0 ? '+' : ''}#{return_pct}%" : "N/A"

    "#{ticker} (#{action}) - #{return_str}"
  end

  # Class method to record recommendations from briefing
  def self.record_from_analysis(video:, analysis:, date: Date.current)
    return [] unless analysis[:recommended_tickers].present?

    trade_reco = analysis.dig(:detailed_analysis, :trade_recommendation) || {}

    analysis[:recommended_tickers].map do |ticker|
      create(
        ticker: ticker.upcase,
        action: analysis[:action] || "WATCH",
        recommended_price: trade_reco[:entry_point]&.to_s&.gsub(/[^0-9.]/, '')&.to_f,
        target_price: trade_reco[:target_price]&.to_s&.gsub(/[^0-9.]/, '')&.to_f,
        stop_loss: trade_reco[:stop_loss]&.to_s&.gsub(/[^0-9.]/, '')&.to_f,
        position_size: trade_reco[:position_size],
        time_horizon: trade_reco[:time_horizon],
        confidence: analysis[:confidence_level] || "medium",
        video_title: video[:title],
        briefing_date: date,
        notes: analysis[:investment_opinion]
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to record recommendation: #{e.message}"
    []
  end
end
