# frozen_string_literal: true

class MorningBriefingJob < ApplicationJob
  queue_as :default

  # Retry on transient errors
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(date: Date.current)
    Rails.logger.info "Starting morning briefing job for #{date}"

    # Initialize services
    youtube_crawler = YoutubeCrawler.new
    transcript_fetcher = TranscriptFetcher.new
    market_fetcher = MarketDataFetcher.new
    analyzer = GeminiAnalyzer.new
    telegram_bot = TelegramBotService.new

    # 1. Fetch market data
    Rails.logger.info "Fetching market data..."
    market_data = market_fetcher.fetch_all

    # 2. Fetch videos from YouTube
    Rails.logger.info "Fetching YouTube videos..."
    videos = youtube_crawler.fetch_morning_videos(date: date)

    if videos.empty?
      Rails.logger.info "No videos found for #{date}"
      telegram_bot.send_message("📭 #{date.strftime('%Y.%m.%d')} 모닝 브리핑\n\n해당 시간대에 새로운 영상이 없습니다.")
      return
    end

    Rails.logger.info "Processing ALL #{videos.size} videos (no limit)"

    # 3. Process each video (brief summary only - detailed on-demand)
    processed_videos = videos.map.with_index do |video, index|
      Rails.logger.info "Processing video #{index + 1}/#{videos.size}: #{video[:title]}"

      # Fetch transcript
      transcript = transcript_fetcher.fetch(video[:id])
      Rails.logger.info transcript ? "Transcript fetched" : "No transcript available"

      # Generate brief summary only (detailed analysis on-demand when button clicked)
      brief_analysis = analyzer.brief_summary(
        video: video,
        transcript: transcript,
        market_data: market_data
      )

      # Record recommendations to DB for tracking
      if brief_analysis[:recommended_tickers].present? && brief_analysis[:action] == "BUY"
        Recommendation.record_from_analysis(
          video: video,
          analysis: brief_analysis,
          date: date
        )
        Rails.logger.info "Recorded recommendations: #{brief_analysis[:recommended_tickers].join(', ')}"
      end

      # Store transcript in cache for on-demand detailed analysis
      if transcript.present?
        Rails.cache.write("transcript:#{video[:id]}", transcript, expires_in: 24.hours)
      end

      {
        video: video,
        transcript: transcript.present?,
        brief_analysis: brief_analysis,
        detailed_analysis: nil  # Generated on-demand when button clicked
      }
    end

    # 4. Generate the ONE LINE insight
    Rails.logger.info "Generating one-line insight..."
    one_line_insight = analyzer.generate_one_line_insight(
      videos_analysis: processed_videos,
      market_data: market_data
    )

    # 5. Send briefing via Telegram
    Rails.logger.info "Sending Telegram briefing..."
    briefing_data = {
      date: date,
      market_data: market_data,
      videos: processed_videos,
      one_line_insight: one_line_insight
    }

    telegram_bot.send_morning_briefing(briefing_data)

    Rails.logger.info "Morning briefing completed successfully"
  rescue StandardError => e
    Rails.logger.error "Morning briefing job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Notify about failure
    begin
      TelegramBotService.new.send_message(
        "⚠️ 모닝 브리핑 생성 중 오류가 발생했습니다.\n\n#{e.message}"
      )
    rescue StandardError
      # Ignore notification errors
    end

    raise # Re-raise for retry
  end
end
