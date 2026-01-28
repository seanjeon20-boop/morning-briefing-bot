# frozen_string_literal: true

require "httparty"
require "json"

class TranscriptFetcher
  TRANSCRIPT_API_URL = "https://www.youtube.com/watch"
  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

  # Fetch transcript for a YouTube video
  # @param video_id [String] YouTube video ID
  # @return [String, nil] Transcript text or nil if not available
  def fetch(video_id)
    transcript_data = fetch_transcript_data(video_id)
    return nil if transcript_data.nil?

    parse_transcript(transcript_data)
  rescue StandardError => e
    Rails.logger.error "Transcript fetch error for #{video_id}: #{e.message}"
    nil
  end

  private

  def fetch_transcript_data(video_id)
    # First, get the video page to extract the captions track URL
    response = HTTParty.get(
      "#{TRANSCRIPT_API_URL}?v=#{video_id}",
      headers: { "User-Agent" => USER_AGENT }
    )

    return nil unless response.success?

    html = response.body

    # Extract the captions data from the page
    captions_match = html.match(/"captions":\s*(\{[^}]+\}[^}]+\})/)
    return nil unless captions_match

    # Find the timedtext URL
    timedtext_match = html.match(%r{"baseUrl":"(https://www\.youtube\.com/api/timedtext[^"]+)"})
    return nil unless timedtext_match

    timedtext_url = timedtext_match[1].gsub("\\u0026", "&")

    # Fetch the actual transcript
    fetch_timedtext(timedtext_url)
  end

  def fetch_timedtext(url)
    # Prefer English captions, try auto-generated if manual not available
    urls_to_try = [
      url.gsub(/&lang=[^&]+/, "&lang=en"),
      url,
      url + "&tlang=en"
    ].uniq

    urls_to_try.each do |try_url|
      response = HTTParty.get(try_url, headers: { "User-Agent" => USER_AGENT })
      return response.body if response.success? && response.body.present?
    end

    nil
  end

  def parse_transcript(xml_data)
    # Parse XML transcript format
    # Format: <transcript><text start="0.0" dur="1.0">Text here</text>...</transcript>
    texts = []

    xml_data.scan(/<text[^>]*>([^<]+)<\/text>/).each do |match|
      text = match[0]
      # Decode HTML entities
      text = decode_html_entities(text)
      texts << text
    end

    return nil if texts.empty?

    # Join all text segments
    texts.join(" ").strip
  end

  def decode_html_entities(text)
    text
      .gsub("&amp;", "&")
      .gsub("&lt;", "<")
      .gsub("&gt;", ">")
      .gsub("&quot;", '"')
      .gsub("&#39;", "'")
      .gsub("&apos;", "'")
      .gsub(/&#(\d+);/) { $1.to_i.chr rescue $& }
      .gsub("\n", " ")
      .strip
  end
end
