# frozen_string_literal: true

namespace :telegram do
  desc "Start Telegram bot polling for callback queries"
  task bot: :environment do
    puts "Starting Telegram bot polling..."
    puts "Press Ctrl+C to stop"

    bot_service = TelegramBotService.new
    bot_service.start_polling
  end

  desc "Send a test message to verify bot configuration"
  task test: :environment do
    puts "Sending test message..."

    bot_service = TelegramBotService.new
    bot_service.send_message("🧪 테스트 메시지입니다!\n\n텔레그램 봇이 정상적으로 설정되었습니다.")

    puts "Test message sent successfully!"
  end

  desc "Manually trigger morning briefing"
  task briefing: :environment do
    puts "Triggering morning briefing..."
    MorningBriefingJob.perform_now
    puts "Briefing completed!"
  end

  desc "Trigger morning briefing for a specific date (YYYY-MM-DD)"
  task :briefing_for, [ :date ] => :environment do |_t, args|
    date = Date.parse(args[:date])
    puts "Triggering morning briefing for #{date}..."
    MorningBriefingJob.perform_now(date: date)
    puts "Briefing completed!"
  rescue ArgumentError => e
    puts "Invalid date format. Use YYYY-MM-DD"
    puts e.message
  end

  desc "Trigger update briefing (last 3 hours)"
  task update: :environment do
    puts "Triggering update briefing..."
    UpdateBriefingJob.perform_now
    puts "Update briefing completed!"
  end

  desc "Trigger weekly review"
  task weekly_review: :environment do
    puts "Triggering weekly review..."
    WeeklyReviewJob.perform_now
    puts "Weekly review completed!"
  end

  desc "Show recommendation history"
  task recommendations: :environment do
    recommendations = Recommendation.recent.limit(20)

    if recommendations.empty?
      puts "No recommendations recorded yet."
      return
    end

    puts "\n📊 Recent Recommendations\n"
    puts "=" * 60

    recommendations.each do |r|
      status_emoji = case r.status
      when :winning then "🟢"
      when :losing then "🔴"
      when :target_hit then "🎯"
      when :stopped_out then "⛔"
      else "⚪"
      end

      return_str = r.return_percentage ? "#{r.return_percentage >= 0 ? '+' : ''}#{r.return_percentage}%" : "N/A"

      puts "#{status_emoji} #{r.briefing_date} | #{r.ticker.ljust(6)} | #{r.action.ljust(5)} | #{return_str.rjust(8)}"
      puts "   #{r.video_title.truncate(50)}" if r.video_title
      puts ""
    end
  end
end
