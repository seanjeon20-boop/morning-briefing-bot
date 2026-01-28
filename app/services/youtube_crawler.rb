# frozen_string_literal: true

require "google/apis/youtube_v3"

class YoutubeCrawler
  CHANNELS = {
    cnbc: "UCvJJ_dzjViJCoLf5uKUTwoA",
    yahoo_finance: "UCEAZeUIeJs0IjQiqTCdVSIg",
    bloomberg: "UCIALMKvObZNtJ6AmdCLP7Lg"
  }.freeze

  def initialize
    @youtube = Google::Apis::YoutubeV3::YouTubeService.new
    @youtube.key = ENV.fetch("YOUTUBE_API_KEY")
  end

  # Fetch videos uploaded during sleep hours (KST 23:00 ~ 05:30)
  # @param date [Date] The date to fetch videos for (defaults to today)
  # @return [Array<Hash>] Array of video information hashes
  def fetch_morning_videos(date: Date.current)
    # KST 23:00 (previous day) ~ KST 05:30 (today)
    # Cutoff at 05:30 so processing finishes by 06:00
    kst_today = date.in_time_zone("Asia/Seoul")
    kst_start = (kst_today - 1.day).change(hour: 23)           # Yesterday 23:00 KST
    kst_end = kst_today.change(hour: 5, min: 30)               # Today 05:30 KST

    fetch_videos_in_range(kst_start, kst_end)
  end

  # Fetch videos uploaded in a custom time range
  # @param start_time [Time] Start time (KST)
  # @param end_time [Time] End time (KST)
  # @return [Array<Hash>] Array of video information hashes
  def fetch_videos_in_range(start_time, end_time)
    # Convert to UTC for YouTube API
    utc_start = start_time.utc
    utc_end = end_time.utc

    videos = []

    CHANNELS.each do |channel_name, channel_id|
      channel_videos = fetch_channel_videos(channel_id, utc_start, utc_end)
      channel_videos.each do |video|
        video[:channel] = format_channel_name(channel_name)
      end
      videos.concat(channel_videos)
    end

    # Sort by published date (newest first)
    videos.sort_by { |v| v[:published_at] }.reverse
  end

  private

  def format_channel_name(channel_name)
    case channel_name
    when :yahoo_finance then "Yahoo Finance"
    when :cnbc then "CNBC"
    when :bloomberg then "Bloomberg"
    else channel_name.to_s.titleize
    end
  end

  def fetch_channel_videos(channel_id, published_after, published_before)
    videos = []

    begin
      # Search for videos from this channel within the time range
      response = @youtube.list_searches(
        "snippet",
        channel_id: channel_id,
        published_after: published_after.iso8601,
        published_before: published_before.iso8601,
        type: "video",
        order: "date",
        max_results: 50
      )

      return videos if response.items.blank?

      # Get detailed video information
      video_ids = response.items.map { |item| item.id.video_id }.compact
      return videos if video_ids.empty?

      details_response = @youtube.list_videos(
        "snippet,contentDetails,statistics",
        id: video_ids.join(",")
      )

      details_response.items.each do |video|
        videos << parse_video(video)
      end
    rescue Google::Apis::Error => e
      Rails.logger.error "YouTube API Error: #{e.message}"
    end

    videos
  end

  def parse_video(video)
    snippet = video.snippet
    content_details = video.content_details
    statistics = video.statistics

    {
      id: video.id,
      title: snippet.title,
      description: snippet.description,
      published_at: snippet.published_at,
      thumbnail_url: snippet.thumbnails&.high&.url || snippet.thumbnails&.default&.url,
      duration: parse_duration(content_details&.duration),
      view_count: statistics&.view_count&.to_i || 0,
      url: "https://www.youtube.com/watch?v=#{video.id}"
    }
  end

  # Parse ISO 8601 duration (e.g., "PT4M13S" -> "4:13")
  def parse_duration(iso_duration)
    return "0:00" if iso_duration.blank?

    match = iso_duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
    return "0:00" unless match

    hours = match[1].to_i
    minutes = match[2].to_i
    seconds = match[3].to_i

    if hours > 0
      format("%d:%02d:%02d", hours, minutes, seconds)
    else
      format("%d:%02d", minutes, seconds)
    end
  end
end
