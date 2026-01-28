# frozen_string_literal: true

class WeeklyReviewJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting weekly review job"

    telegram_bot = TelegramBotService.new
    analyzer = GeminiAnalyzer.new

    # Get this week's recommendations
    recommendations = Recommendation.this_week.buys.recent

    if recommendations.empty?
      telegram_bot.send_message("📊 *주간 리뷰*\n\n이번 주 추천 종목이 없습니다.")
      return
    end

    # Update current prices (simplified - in production would use real-time API)
    update_prices(recommendations)

    # Generate review
    review = analyzer.generate_weekly_review(
      recommendations: recommendations.map do |r|
        {
          date: r.briefing_date,
          ticker: r.ticker,
          action: r.action,
          recommended_price: r.recommended_price,
          current_price: r.current_price
        }
      end
    )

    # Build message
    message = build_review_message(recommendations, review)
    telegram_bot.send_message(message)

    Rails.logger.info "Weekly review completed"
  rescue StandardError => e
    Rails.logger.error "Weekly review failed: #{e.message}"
  end

  private

  def update_prices(recommendations)
    fetcher = MarketDataFetcher.new

    recommendations.each do |reco|
      # Note: Would need a proper stock quote API for real prices
      # For now, this is a placeholder
      # reco.update(current_price: fetcher.fetch_stock_price(reco.ticker))
    end
  end

  def build_review_message(recommendations, review)
    winning = recommendations.select { |r| r.return_percentage && r.return_percentage > 0 }
    losing = recommendations.select { |r| r.return_percentage && r.return_percentage < 0 }

    lines = [
      "📊 *주간 성과 리뷰*",
      "",
      "━━━━━━━━━━━━━━━━━━",
      "",
      "📈 *이번 주 추천 종목*"
    ]

    recommendations.each do |r|
      emoji = case r.status
      when :winning then "🟢"
      when :losing then "🔴"
      when :target_hit then "🎯"
      when :stopped_out then "⛔"
      else "⚪"
      end

      return_str = r.return_percentage ? "#{r.return_percentage >= 0 ? '+' : ''}#{r.return_percentage}%" : "N/A"
      lines << "#{emoji} #{r.ticker}: #{return_str}"
    end

    lines << ""
    lines << "━━━━━━━━━━━━━━━━━━"
    lines << ""

    if review[:total_return]
      lines << "💰 *총 수익률*: #{review[:total_return]}"
      lines << "📊 *승률*: #{review[:win_rate]} (#{review[:winning_trades]}/#{review[:total_recommendations]})"
    end

    if review[:best_pick]
      lines << ""
      lines << "🏆 *베스트 픽*: #{review[:best_pick][:ticker]} (#{review[:best_pick][:return]})"
    end

    if review[:worst_pick]
      lines << "📉 *최악의 픽*: #{review[:worst_pick][:ticker]} (#{review[:worst_pick][:return]})"
    end

    if review[:lessons_learned]
      lines << ""
      lines << "📝 *이번 주 교훈*"
      lines << review[:lessons_learned]
    end

    if review[:next_week_outlook]
      lines << ""
      lines << "🔮 *다음 주 전망*"
      lines << review[:next_week_outlook]
    end

    if review[:key_events_next_week]&.any?
      lines << ""
      lines << "📅 *다음 주 주요 이벤트*"
      review[:key_events_next_week].each { |event| lines << "• #{event}" }
    end

    lines.join("\n")
  end
end
