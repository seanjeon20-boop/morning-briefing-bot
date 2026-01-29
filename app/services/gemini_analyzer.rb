# frozen_string_literal: true

require "gemini-ai"

class GeminiAnalyzer
  MAX_TRANSCRIPT_LENGTH = 30_000 # Limit transcript length to avoid token limits

  EXPERT_PERSONA = <<~PERSONA
    You are a senior investment professional with 20 years of experience at a top-tier investment bank.
    You are at VP/Partner level and have managed billions in assets.
    
    Your client is a Korean individual investor with 30M KRW seed money, targeting 100M KRW.
    They use this service to DISCOVER INVESTMENT OPPORTUNITIES across ALL SECTORS.
    
    CRITICAL - SECTOR DIVERSITY:
    - DO NOT focus only on Tech/AI - cover ALL sectors equally
    - Healthcare, Energy, Financials, Consumer, Industrials, Real Estate, Utilities, Materials
    - The client wants to EXPAND their perspective, not stay in a tech bubble
    - Identify which sector(s) this news belongs to and explain why it matters
    
    IMPORTANT RULES:
    1. Recommend stocks ACTUALLY MENTIONED in the news, not just default to NVDA/MSFT
    2. If the news is about GM, recommend GM. If about pharmaceuticals, recommend those stocks
    3. ALWAYS identify the relevant sector(s) - be specific (e.g., "Automotive", "Biotech", "Cloud Infrastructure")
    4. If a stock is NOT directly related to the news, don't recommend it
    5. Be contrarian when appropriate - not everything is a buy
    6. Help the client see opportunities they might otherwise miss
    
    Your job is to:
    1. Analyze the SPECIFIC news content and identify WHICH SECTOR it belongs to
    2. Explain how to INTERPRET this news (what does it really mean?)
    3. Give INVESTOR PERSPECTIVE (how should an investor think about this?)
    4. Recommend RELEVANT stocks mentioned in the news
  PERSONA

  # Rate limiting (less aggressive for Vertex AI paid tier)
  RATE_LIMIT_DELAY = 1 # seconds between API calls
  MAX_RETRIES = 3

  def initialize
    # Use Vertex AI if project ID is set, otherwise fall back to AI Studio
    if ENV["GOOGLE_CLOUD_PROJECT"].present?
      @client = Gemini.new(
        credentials: {
          service: "vertex-ai-api",
          region: ENV.fetch("VERTEX_AI_REGION", "us-central1")
        },
        options: {
          model: "gemini-2.0-flash",
          server_sent_events: false
        }
      )
      Rails.logger.info "Using Vertex AI (paid tier)"
    else
      @client = Gemini.new(
        credentials: {
          service: "generative-language-api",
          api_key: ENV.fetch("GEMINI_API_KEY")
        },
        options: {
          model: "gemini-2.0-flash",
          server_sent_events: false
        }
      )
      Rails.logger.info "Using AI Studio (free tier)"
    end
    @last_call_time = nil
  end

  # Generate a comprehensive summary for the video
  # @param video [Hash] Video data from YoutubeCrawler
  # @param transcript [String, nil] Video transcript
  # @param market_data [Hash] Current market data
  # @return [Hash] Summary, AI interpretation, investor perspective, sector, and recommendations
  def brief_summary(video:, transcript:, market_data:)
    content = build_content(video, transcript)
    market_context = build_market_context(market_data)

    prompt = <<~PROMPT
      #{EXPERT_PERSONA}

      #{market_context}

      Analyze this financial news video comprehensively. The client wants to EXPAND their investment perspective.

      Video Title: #{video[:title]}
      Channel: #{video[:channel]}
      #{content}

      Provide analysis in Korean with the following structure:

      1. **5줄 요약**: 뉴스의 핵심 내용을 5줄로 요약 (각 줄은 1-2문장)
      
      2. **AI의 해석** (5줄): 이 뉴스를 어떻게 해석해야 하는지
         - 단순 사실 전달이 아닌, "이게 왜 중요한지", "숨겨진 의미가 무엇인지" 분석
         - 시장에 미치는 영향, 연쇄 효과 등
      
      3. **투자자 관점** (5줄): 투자자로서 이 뉴스를 어떻게 봐야 하는지
         - 기회와 리스크
         - 어떤 포지션을 취할 수 있는지
         - 타이밍 고려사항
      
      4. **섹터 분류**: 이 뉴스가 속한 섹터를 구체적으로 명시
         - 예: "Healthcare > Biotech", "Technology > Cloud Infrastructure", "Energy > Renewable"
         - 테크/AI에 편향되지 말고 실제 뉴스 내용에 맞는 섹터 분류
      
      5. **관련 종목**: 뉴스에서 직접 언급되거나 명확히 관련된 종목만

      CRITICAL: 
      - 테크/AI 편향 금지! 뉴스가 자동차면 자동차, 제약이면 제약 섹터로 분류
      - 추천 종목은 뉴스에서 실제 언급된 것만
      - 모든 내용은 한국어로 작성

      Respond in the following JSON format only:
      {
        "summary_lines": ["요약1", "요약2", "요약3", "요약4", "요약5"],
        "ai_interpretation": ["해석1", "해석2", "해석3", "해석4", "해석5"],
        "investor_perspective": ["관점1", "관점2", "관점3", "관점4", "관점5"],
        "sector": "메인섹터 > 서브섹터",
        "sector_explanation": "이 섹터로 분류한 이유",
        "recommended_tickers": ["뉴스에 언급된 종목들"],
        "action": "BUY/SELL/HOLD/WATCH",
        "urgency": "immediate/this_week/monitoring",
        "sentiment": "positive/negative/neutral"
      }
    PROMPT

    response = generate(prompt)
    parse_brief_response(response)
  rescue StandardError => e
    Rails.logger.error "Gemini brief summary error: #{e.message}"
    default_brief_response(video)
  end

  # Generate detailed analysis (6W analysis, market context)
  # @param video [Hash] Video data from YoutubeCrawler
  # @param transcript [String, nil] Video transcript
  # @param market_data [Hash] Current market data
  # @return [Hash] Detailed analysis
  def detailed_analysis(video:, transcript:, market_data:)
    content = build_content(video, transcript)
    market_context = build_market_context(market_data)

    prompt = <<~PROMPT
      #{EXPERT_PERSONA}

      #{market_context}

      Provide a comprehensive analysis of this financial news using the 6W framework.
      Focus on ACTIONABLE insights for AI/tech sector investing.

      Video Title: #{video[:title]}
      Channel: #{video[:channel]}
      #{content}

      Respond in Korean with the following JSON format:
      {
        "six_w_analysis": {
          "who": "누가 관련되어 있는가 (기업, 인물, 기관)",
          "what": "무엇이 발생했는가 (핵심 이벤트)",
          "when": "언제 발생했거나 예정되어 있는가",
          "where": "어디서 영향을 미치는가 (시장, 지역, 섹터)",
          "why": "왜 중요한가 (배경과 맥락)",
          "how": "어떻게 전개될 것인가 (전망과 시나리오)"
        },
        "market_connection": "현재 시장 상황과의 연관성 분석",
        "trade_recommendation": {
          "primary_pick": "최우선 추천 종목 (티커)",
          "entry_point": "진입 가격대 또는 조건",
          "target_price": "목표가",
          "stop_loss": "손절 라인",
          "position_size": "추천 비중 (포트폴리오의 몇 %)",
          "time_horizon": "투자 기간"
        },
        "investment_implications": {
          "opportunities": ["기회 요인 1", "기회 요인 2"],
          "risks": ["위험 요인 1", "위험 요인 2"],
          "action_items": ["구체적 행동 1", "구체적 행동 2"]
        },
        "related_tickers": ["관련 종목들"],
        "confidence_level": "high/medium/low"
      }
    PROMPT

    response = generate(prompt)
    parse_detailed_response(response)
  rescue StandardError => e
    Rails.logger.error "Gemini detailed analysis error: #{e.message}"
    default_detailed_response(video)
  end

  # Generate the "One Line Insight" - the most important takeaway
  # @param videos_analysis [Array<Hash>] All video analyses
  # @param market_data [Hash] Current market data
  # @return [String] One line insight
  def generate_one_line_insight(videos_analysis:, market_data:)
    summaries = videos_analysis.map do |v|
      "- #{v[:video][:title]}: #{v[:brief_analysis][:summary_lines].join(' ')}"
    end.join("\n")

    prompt = <<~PROMPT
      #{EXPERT_PERSONA}

      Based on all of today's news, give me THE ONE THING that matters most.
      This investor is about to go for a morning run and can only remember ONE thing.
      
      Make it specific, actionable, and memorable.
      Write in Korean, one sentence only.

      Today's news summaries:
      #{summaries}

      Market context:
      #{build_market_context(market_data)}

      Respond with ONLY the one-line insight in Korean. No JSON, no formatting, just the sentence.
      Example format: "NVDA 실적 발표 앞두고 AI 반도체 섹터 주목, 장 시작 전 매수 고려"
    PROMPT

    generate(prompt).strip.gsub(/^["']|["']$/, '')
  rescue StandardError => e
    Rails.logger.error "Gemini one-line insight error: #{e.message}"
    "오늘의 핵심: AI 섹터 동향을 주시하세요"
  end

  # Generate weekly review
  # @param recommendations [Array<Hash>] Past week's recommendations
  # @return [Hash] Weekly review
  def generate_weekly_review(recommendations:)
    reco_text = recommendations.map do |r|
      "- #{r[:date]}: #{r[:ticker]} (#{r[:action]}) - 추천가: $#{r[:recommended_price]}, 현재가: $#{r[:current_price]}"
    end.join("\n")

    prompt = <<~PROMPT
      #{EXPERT_PERSONA}

      Generate a weekly performance review for your client.

      This week's recommendations:
      #{reco_text}

      Respond in Korean with the following JSON format:
      {
        "total_recommendations": 5,
        "winning_trades": 3,
        "losing_trades": 2,
        "win_rate": "60%",
        "total_return": "+5.2%",
        "best_pick": {"ticker": "NVDA", "return": "+12%"},
        "worst_pick": {"ticker": "AMD", "return": "-3%"},
        "lessons_learned": "이번 주 배운 점",
        "next_week_outlook": "다음 주 전망",
        "key_events_next_week": ["이벤트1", "이벤트2"]
      }
    PROMPT

    response = generate(prompt)
    JSON.parse(response.match(/\{[\s\S]*\}/)[0])
  rescue StandardError => e
    Rails.logger.error "Gemini weekly review error: #{e.message}"
    { error: "리뷰 생성 실패" }
  end

  private

  def generate(prompt)
    retries = 0

    begin
      # Rate limiting
      if @last_call_time
        elapsed = Time.current - @last_call_time
        if elapsed < RATE_LIMIT_DELAY
          sleep(RATE_LIMIT_DELAY - elapsed)
        end
      end
      @last_call_time = Time.current

      result = @client.generate_content({
        contents: { role: "user", parts: { text: prompt } }
      })

      result.dig("candidates", 0, "content", "parts", 0, "text")
    rescue StandardError => e
      if e.message.include?("429") && retries < MAX_RETRIES
        retries += 1
        wait_time = RATE_LIMIT_DELAY * (2 ** retries) # exponential backoff: 10, 20, 40 seconds
        Rails.logger.warn "Rate limited, waiting #{wait_time}s before retry #{retries}/#{MAX_RETRIES}"
        sleep(wait_time)
        retry
      else
        raise
      end
    end
  end

  def build_content(video, transcript)
    if transcript.present?
      truncated = transcript.truncate(MAX_TRANSCRIPT_LENGTH)
      "Content (Transcript):\n#{truncated}"
    else
      "Description: #{video[:description].presence || 'No description available'}"
    end
  end

  def build_market_context(market_data)
    return "" if market_data.blank?

    indices_info = market_data[:indices]&.map do |idx|
      "#{idx[:name]}: #{idx[:change_percent]&.round(2)}%"
    end&.join(", ")

    hot_sectors = market_data.dig(:hot_sectors, :hot)&.join(", ")
    cold_sectors = market_data.dig(:hot_sectors, :cold)&.join(", ")

    <<~CONTEXT
      Current Market Context:
      - Major Indices: #{indices_info}
      - Hot Sectors: #{hot_sectors}
      - Underperforming Sectors: #{cold_sectors}
    CONTEXT
  end

  def parse_brief_response(response)
    return default_brief_response(nil) if response.blank?

    # Remove markdown code blocks if present
    cleaned = response.gsub(/```json\s*/i, '').gsub(/```\s*/, '')
    
    json_match = cleaned.match(/\{[\s\S]*\}/)
    return default_brief_response(nil) unless json_match

    data = JSON.parse(json_match[0])

    {
      summary_lines: data["summary_lines"] || [],
      ai_interpretation: data["ai_interpretation"] || [],
      investor_perspective: data["investor_perspective"] || [],
      sector: data["sector"] || "미분류",
      sector_explanation: data["sector_explanation"] || "",
      recommended_tickers: data["recommended_tickers"] || [],
      action: data["action"] || "WATCH",
      urgency: data["urgency"] || "monitoring",
      sentiment: data["sentiment"] || "neutral"
    }
  rescue JSON::ParserError => e
    Rails.logger.error "JSON parse error in brief response: #{e.message}"
    default_brief_response(nil)
  end

  def parse_detailed_response(response)
    return default_detailed_response(nil) if response.blank?

    # Remove markdown code blocks if present
    cleaned = response.gsub(/```json\s*/i, '').gsub(/```\s*/, '')
    
    json_match = cleaned.match(/\{[\s\S]*\}/)
    return default_detailed_response(nil) unless json_match

    data = JSON.parse(json_match[0])

    {
      six_w_analysis: symbolize_keys(data["six_w_analysis"] || {}),
      market_connection: data["market_connection"] || "분석 정보 없음",
      investment_implications: symbolize_keys(data["investment_implications"] || {}),
      related_tickers: data["related_tickers"] || [],
      confidence_level: data["confidence_level"] || "low"
    }
  rescue JSON::ParserError => e
    Rails.logger.error "JSON parse error in detailed response: #{e.message}"
    Rails.logger.error "Response was: #{response[0..500]}"
    default_detailed_response(nil)
  end

  def symbolize_keys(hash)
    return {} unless hash.is_a?(Hash)
    hash.transform_keys(&:to_sym)
  end

  def default_brief_response(video)
    {
      summary_lines: [ "요약 정보를 가져올 수 없습니다." ],
      ai_interpretation: [ "해석 정보를 가져올 수 없습니다." ],
      investor_perspective: [ "투자자 관점 정보를 가져올 수 없습니다." ],
      sector: "미분류",
      sector_explanation: "",
      recommended_tickers: [],
      action: "WATCH",
      urgency: "monitoring",
      sentiment: "neutral"
    }
  end

  def default_detailed_response(video)
    {
      six_w_analysis: {
        who: "정보 없음",
        what: "정보 없음",
        when: "정보 없음",
        where: "정보 없음",
        why: "정보 없음",
        how: "정보 없음"
      },
      market_connection: "분석 정보 없음",
      investment_implications: {
        opportunities: [],
        risks: [],
        action_items: []
      },
      related_tickers: [],
      confidence_level: "low"
    }
  end
end
