# frozen_string_literal: true

# Morning Briefing Configuration
Rails.application.config.to_prepare do
  # Validate required environment variables in production
  if Rails.env.production?
    required_vars = %w[
      YOUTUBE_API_KEY
      GEMINI_API_KEY
      TELEGRAM_BOT_TOKEN
      TELEGRAM_CHAT_ID
    ]

    missing_vars = required_vars.select { |var| ENV[var].blank? }

    if missing_vars.any?
      Rails.logger.warn "Missing required environment variables for Morning Briefing: #{missing_vars.join(', ')}"
    end
  end
end
