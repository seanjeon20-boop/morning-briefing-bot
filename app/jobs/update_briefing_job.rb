# frozen_string_literal: true

class UpdateBriefingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Runs every 3 hours after 6am KST
  # Fetches videos uploaded since the last briefing
  def perform
    Rails.logger.info "Starting update briefing job"

    # Calculate time range: last 3 hours
    kst_now = Time.current.in_time_zone("Asia/Seoul")
    kst_end = kst_now
    kst_start = kst_now - 3.hours

    Rails.logger.info "Fetching videos from #{kst_start.strftime('%H:%M')} to #{kst_end.strftime('%H:%M')} KST"

    # Initialize services
    youtube_crawler = YoutubeCrawler.new
    transcript_fetcher = TranscriptFetcher.new
    market_fetcher = MarketDataFetcher.new
    analyzer = GeminiAnalyzer.new
    telegram_bot = TelegramBotService.new

    # Fetch market data
    Rails.logger.info "Fetching market data..."
    market_data = market_fetcher.fetch_all

    # Fetch videos in range
    Rails.logger.info "Fetching YouTube videos..."
    videos = youtube_crawler.fetch_videos_in_range(kst_start, kst_end)

    if videos.empty?
      Rails.logger.info "No new videos in the last 3 hours"
      # Don't send message if no videos - avoid spam
      return
    end

    Rails.logger.info "Processing ALL #{videos.size} new videos"

    # Process each video (brief summary only - detailed on-demand)
    processed_videos = videos.map.with_index do |video, index|
      Rails.logger.info "Processing video #{index + 1}/#{videos.size}: #{video[:title]}"

      transcript = transcript_fetcher.fetch(video[:id])
      Rails.logger.info transcript ? "Transcript fetched" : "No transcript available"

      brief_analysis = analyzer.brief_summary(
        video: video,
        transcript: transcript,
        market_data: market_data
      )

      # Record recommendations
      if brief_analysis[:recommended_tickers].present? && brief_analysis[:action] == "BUY"
        Recommendation.record_from_analysis(
          video: video,
          analysis: brief_analysis,
          date: Date.current
        )
        Rails.logger.info "Recorded recommendations: #{brief_analysis[:recommended_tickers].join(', ')}"
      end

      # Store transcript for on-demand detailed analysis
      if transcript.present?
        Rails.cache.write("transcript:#{video[:id]}", transcript, expires_in: 24.hours)
      end

      {
        video: video,
        transcript: transcript.present?,
        brief_analysis: brief_analysis,
        detailed_analysis: nil  # On-demand
      }
    end

    # Generate one-line insight
    Rails.logger.info "Generating one-line insight..."
    one_line_insight = analyzer.generate_one_line_insight(
      videos_analysis: processed_videos,
      market_data: market_data
    )

    # Send update briefing
    Rails.logger.info "Sending Telegram update briefing..."
    send_update_briefing(telegram_bot, processed_videos, market_data, one_line_insight, kst_start, kst_end)

    Rails.logger.info "Update briefing completed successfully"
  rescue StandardError => e
    Rails.logger.error "Update briefing job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def send_update_briefing(telegram_bot, processed_videos, market_data, one_line_insight, start_time, end_time)
    time_range = "#{start_time.strftime('%H:%M')} ~ #{end_time.strftime('%H:%M')}"

    # Send header
    header = <<~MSG
      🔄 *업데이트 브리핑* (#{time_range} KST)
      
      새로운 영상 #{processed_videos.size}개 분석 완료
    MSG
    telegram_bot.send_message(header)

    # Send each video summary using existing method
    briefing_data = {
      date: Date.current,
      market_data: market_data,
      videos: processed_videos,
      one_line_insight: one_line_insight
    }

    telegram_bot.send_morning_briefing(briefing_data)
  end
end
