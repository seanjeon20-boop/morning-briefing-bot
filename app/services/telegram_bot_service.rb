# frozen_string_literal: true

require "telegram/bot"

class TelegramBotService
  MAX_MESSAGE_LENGTH = 4096

  def initialize
    @token = ENV.fetch("TELEGRAM_BOT_TOKEN")
    @chat_id = ENV.fetch("TELEGRAM_CHAT_ID")
  end

  # Send the morning briefing message
  # @param briefing_data [Hash] Complete briefing data
  def send_morning_briefing(briefing_data)
    Telegram::Bot::Client.run(@token) do |bot|
      # Send market summary first
      send_market_summary(bot, briefing_data[:market_data])

      # Send each video summary with inline buttons
      briefing_data[:videos].each_with_index do |video_data, index|
        send_video_summary(bot, video_data, index)
        sleep(0.5) # Rate limiting
      end

      # Send closing message
      send_closing_message(bot, briefing_data)
    end
  end

  # Send a single message
  # @param text [String] Message text
  # @param parse_mode [String] Parse mode (Markdown or HTML)
  def send_message(text, parse_mode: "Markdown")
    Telegram::Bot::Client.run(@token) do |bot|
      bot.api.send_message(
        chat_id: @chat_id,
        text: truncate_message(text),
        parse_mode: parse_mode
      )
    end
  end

  # Handle callback query (when user clicks inline button)
  # @param callback_data [String] Callback data from button
  # @return [Hash, nil] Detailed analysis data or nil
  def handle_callback(callback_data)
    # Callback data format: "detail:video_cache_key"
    return nil unless callback_data.start_with?("detail:")

    cache_key = callback_data.sub("detail:", "")
    Rails.cache.read(cache_key)
  end

  # Start polling for callback queries (run in background)
  def start_polling
    Telegram::Bot::Client.run(@token) do |bot|
      bot.listen do |message|
        case message
        when Telegram::Bot::Types::CallbackQuery
          handle_callback_query(bot, message)
        when Telegram::Bot::Types::Message
          handle_command(bot, message)
        end
      end
    end
  end

  private

  def send_market_summary(bot, market_data)
    text = build_market_summary_text(market_data)
    bot.api.send_message(
      chat_id: @chat_id,
      text: text,
      parse_mode: "Markdown"
    )
  end

  def build_market_summary_text(market_data)
    lines = [
      "📊 *#{Date.current.strftime('%Y.%m.%d')} 모닝 브리핑*",
      "",
      "*\\[시장 현황\\]*"
    ]

    market_data[:indices]&.each do |index|
      emoji = index[:direction] == :up ? "🟢" : "🔴"
      sign = index[:change] >= 0 ? "+" : ""
      price = format_number(index[:price])
      change = "#{sign}#{index[:change_percent].round(2)}%"
      lines << "#{emoji} #{index[:name]}: #{price} (#{change})"
    end

    if market_data.dig(:hot_sectors, :hot)&.any?
      lines << ""
      lines << "🔥 *핫 섹터*: #{market_data[:hot_sectors][:hot].join(', ')}"
    end

    if market_data.dig(:hot_sectors, :cold)&.any?
      lines << "❄️ *부진 섹터*: #{market_data[:hot_sectors][:cold].join(', ')}"
    end

    lines.join("\n")
  end

  def send_video_summary(bot, video_data, index)
    video = video_data[:video]
    analysis = video_data[:brief_analysis]

    # Build message text
    text = build_video_summary_text(video, analysis, index)

    # Store video info in cache for on-demand detailed analysis
    cache_key = "briefing:video:#{video[:id]}"
    Rails.cache.write(cache_key, {
      video: video,
      has_transcript: video_data[:transcript]
    }, expires_in: 24.hours)

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
      inline_keyboard: [
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "📖 상세 분석 보기",
            callback_data: "detail:#{video[:id]}"
          ),
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🎬 영상 보기",
            url: video[:url]
          )
        ]
      ]
    )

    bot.api.send_message(
      chat_id: @chat_id,
      text: truncate_message(text),
      parse_mode: "Markdown",
      reply_markup: keyboard
    )
  end

  def build_video_summary_text(video, analysis, index)
    sentiment_emoji = case analysis[:sentiment]
    when "positive" then "📈"
    when "negative" then "📉"
    else "📊"
    end

    action_emoji = case analysis[:action]
    when "BUY" then "🟢 매수"
    when "SELL" then "🔴 매도"
    when "HOLD" then "🟡 보유"
    when "WATCH" then "👀 관망"
    else "📋 분석"
    end

    lines = [
      "",
      "━━━━━━━━━━━━━━━━━━",
      "#{sentiment_emoji} *#{index + 1}. #{escape_markdown(video[:title])}*",
      "📺 #{video[:channel]} | ⏱ #{video[:duration]}",
      ""
    ]

    # 섹터 표시
    if analysis[:sector].present? && analysis[:sector] != "미분류"
      lines << "🏷 *섹터*: #{escape_markdown(analysis[:sector])}"
      lines << ""
    end

    # 5줄 요약
    lines << "📝 *요약*"
    analysis[:summary_lines].each_with_index do |line, i|
      lines << "#{i + 1}. #{escape_markdown(line)}"
    end

    # AI 해석 (5줄)
    if analysis[:ai_interpretation]&.any?
      lines << ""
      lines << "🤖 *AI의 해석*"
      analysis[:ai_interpretation].each do |line|
        lines << "• #{escape_markdown(line)}"
      end
    end

    # 투자자 관점 (5줄)
    if analysis[:investor_perspective]&.any?
      lines << ""
      lines << "💰 *투자자 관점*"
      analysis[:investor_perspective].each do |line|
        lines << "• #{escape_markdown(line)}"
      end
    end

    # 추천 종목 & 액션
    if analysis[:recommended_tickers]&.any?
      lines << ""
      lines << "#{action_emoji}"
      lines << "🎯 *관련 종목*: #{analysis[:recommended_tickers].join(', ')}"
    end

    lines.join("\n")
  end

  def send_closing_message(bot, briefing_data)
    video_count = briefing_data[:videos].size
    one_line_insight = briefing_data[:one_line_insight] || "AI 섹터 동향을 주시하세요"

    text = <<~MSG
      ━━━━━━━━━━━━━━━━━━

      🎯 *오늘의 핵심 (런닝 가면서 기억할 것)*

      #{escape_markdown(one_line_insight)}

      ━━━━━━━━━━━━━━━━━━

      📌 *브리핑 완료*
      총 #{video_count}개 영상 분석

      _각 영상의 "상세 분석 보기" 버튼을 클릭하면_
      _6하원칙 분석과 구체적 매매 전략을 확인할 수 있습니다._

      _화이팅! 🏃‍♂️_
    MSG

    bot.api.send_message(
      chat_id: @chat_id,
      text: text,
      parse_mode: "Markdown"
    )
  end

  def handle_callback_query(bot, callback_query)
    callback_data = callback_query.data
    chat_id = callback_query.message.chat.id

    # Acknowledge the callback with loading message
    bot.api.answer_callback_query(
      callback_query_id: callback_query.id,
      text: "상세 분석 생성 중... 잠시만 기다려주세요"
    )

    # Extract video ID from callback data
    return unless callback_data.start_with?("detail:")
    video_id = callback_data.sub("detail:", "")

    # Get video info from cache
    video_cache_key = "briefing:video:#{video_id}"
    video_info = Rails.cache.read(video_cache_key)

    unless video_info
      bot.api.send_message(
        chat_id: chat_id,
        text: "⚠️ 비디오 정보를 찾을 수 없습니다. (24시간 후 만료)",
        parse_mode: "Markdown"
      )
      return
    end

    # Check if detailed analysis already cached
    detail_cache_key = "briefing:detail:#{video_id}"
    detailed_analysis = Rails.cache.read(detail_cache_key)

    unless detailed_analysis
      # Generate detailed analysis on-demand
      bot.api.send_message(
        chat_id: chat_id,
        text: "🔄 상세 분석을 생성하고 있습니다... (약 10초 소요)"
      )

      transcript = Rails.cache.read("transcript:#{video_id}")
      market_data = MarketDataFetcher.new.fetch_all
      analyzer = GeminiAnalyzer.new

      detailed_analysis = analyzer.detailed_analysis(
        video: video_info[:video],
        transcript: transcript,
        market_data: market_data
      )

      # Cache for future requests
      Rails.cache.write(detail_cache_key, detailed_analysis, expires_in: 24.hours)
    end

    text = build_detailed_analysis_text(detailed_analysis)
    bot.api.send_message(
      chat_id: chat_id,
      text: truncate_message(text),
      parse_mode: "Markdown"
    )
  end

  def build_detailed_analysis_text(analysis)
    six_w = analysis[:six_w_analysis] || {}
    implications = analysis[:investment_implications] || {}

    lines = [
      "📋 *상세 분석 (6하원칙)*",
      "",
      "👤 *Who (누가)*",
      escape_markdown(six_w[:who] || "정보 없음"),
      "",
      "📌 *What (무엇)*",
      escape_markdown(six_w[:what] || "정보 없음"),
      "",
      "🕐 *When (언제)*",
      escape_markdown(six_w[:when] || "정보 없음"),
      "",
      "🌍 *Where (어디서)*",
      escape_markdown(six_w[:where] || "정보 없음"),
      "",
      "❓ *Why (왜)*",
      escape_markdown(six_w[:why] || "정보 없음"),
      "",
      "⚙️ *How (어떻게)*",
      escape_markdown(six_w[:how] || "정보 없음"),
      "",
      "━━━━━━━━━━━━━━━━━━",
      "",
      "📊 *시장 연관성*",
      escape_markdown(analysis[:market_connection] || "정보 없음"),
      ""
    ]

    # Investment implications
    if implications[:opportunities]&.any?
      lines << "✅ *기회 요인*"
      implications[:opportunities].each { |o| lines << "• #{escape_markdown(o)}" }
      lines << ""
    end

    if implications[:risks]&.any?
      lines << "⚠️ *위험 요인*"
      implications[:risks].each { |r| lines << "• #{escape_markdown(r)}" }
      lines << ""
    end

    if implications[:action_items]&.any?
      lines << "📝 *고려할 행동*"
      implications[:action_items].each { |a| lines << "• #{escape_markdown(a)}" }
      lines << ""
    end

    # Related tickers
    if analysis[:related_tickers]&.any?
      lines << "🏷 *관련 종목*: #{analysis[:related_tickers].join(', ')}"
    end

    # Confidence level
    confidence_emoji = case analysis[:confidence_level]
    when "high" then "🟢"
    when "medium" then "🟡"
    else "🔴"
    end
    lines << ""
    lines << "#{confidence_emoji} 신뢰도: #{analysis[:confidence_level]&.upcase || 'N/A'}"

    lines.join("\n")
  end

  def handle_command(bot, message)
    case message.text
    when "/start"
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "👋 모닝 브리핑 봇입니다!\n\n매일 아침 CNBC와 Yahoo Finance의 주요 뉴스를 요약해드립니다."
      )
    when "/briefing"
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "브리핑을 생성하고 있습니다... 잠시만 기다려주세요."
      )
      # Trigger manual briefing job
      MorningBriefingJob.perform_later
    end
  end

  def truncate_message(text)
    return text if text.length <= MAX_MESSAGE_LENGTH

    text[0...MAX_MESSAGE_LENGTH - 3] + "..."
  end

  def escape_markdown(text)
    return "" if text.blank?

    # Escape Markdown special characters
    text.to_s
        .gsub("_", "\\_")
        .gsub("*", "\\*")
        .gsub("[", "\\[")
        .gsub("]", "\\]")
        .gsub("`", "\\`")
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
