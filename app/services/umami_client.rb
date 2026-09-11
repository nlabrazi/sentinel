# frozen_string_literal: true

require "httparty"

class UmamiClient
  include HTTParty

  DEFAULT_BASE_URL = "https://umami.nabster.dev"
  DEFAULT_TIMEOUT = 10

  attr_reader :base_url

  def initialize(base_url: nil)
    @base_url = (base_url.presence || ENV["UMAMI_BASE_URL"].presence || DEFAULT_BASE_URL).to_s.chomp("/")
  end

  def configured?
    auth_token.present? || api_key.present? || (username.present? && password.present?)
  end

  def auth_token
    ENV["UMAMI_AUTH_TOKEN"].presence || (Rails.application.credentials.dig(:umami, :auth_token) rescue nil)
  end

  def api_key
    ENV["UMAMI_API_KEY"].presence || (Rails.application.credentials.dig(:umami, :api_key) rescue nil)
  end

  def username
    ENV["UMAMI_USERNAME"].presence || (Rails.application.credentials.dig(:umami, :username) rescue nil)
  end

  def password
    ENV["UMAMI_PASSWORD"].presence || (Rails.application.credentials.dig(:umami, :password) rescue nil)
  end

  # Returns an array of websites registered in Umami
  def websites
    response = get_request("/api/websites")
    return [] unless response&.success?

    data = response.parsed_response
    if data.is_a?(Hash) && data["data"].is_a?(Array)
      data["data"]
    elsif data.is_a?(Array)
      data
    else
      []
    end
  rescue StandardError => e
    Rails.logger.error("[UmamiClient] Failed to fetch websites: #{e.message}")
    []
  end

  # Finds a website in Umami matching a given domain or URL host
  def find_website_by_domain(domain_or_url)
    return nil if domain_or_url.blank?

    target_host = extract_host(domain_or_url).downcase
    return nil if target_host.blank?

    all_websites = websites
    all_websites.find do |site|
      site_domain = (site["domain"] || site[:domain]).to_s.strip.downcase
      site_domain = extract_host(site_domain)
      site_domain == target_host
    end
  end

  # Fetches 24-hour statistics for a given website ID
  def stats_24h(website_id)
    end_at = (Time.current.to_i * 1000)
    start_at = (24.hours.ago.to_i * 1000)
    stats(website_id, start_at: start_at, end_at: end_at)
  end

  # Generic stats request with start_at and end_at in milliseconds
  def stats(website_id, start_at:, end_at:)
    return { error: "Website ID missing" } if website_id.blank?

    response = get_request("/api/websites/#{website_id}/stats", query: { startAt: start_at, endAt: end_at })
    unless response&.success?
      error_msg = response ? "HTTP #{response.code}: #{response.body}" : "No response"
      Rails.logger.error("[UmamiClient] Failed to fetch stats for #{website_id}: #{error_msg}")
      return { error: error_msg }
    end

    parse_stats_response(response.parsed_response)
  rescue StandardError => e
    Rails.logger.error("[UmamiClient] Error fetching stats for #{website_id}: #{e.message}")
    { error: e.message }
  end

  private

  def get_request(path, query: {}, custom_headers: nil)
    headers = custom_headers || auth_headers
    return nil if headers.nil?

    self.class.get(
      "#{@base_url}#{path}",
      headers: headers,
      query: query,
      timeout: DEFAULT_TIMEOUT
    )
  end

  def auth_headers
    if auth_token.present?
      {
        "Authorization" => "Bearer #{auth_token}",
        "Accept" => "application/json"
      }
    elsif api_key.present?
      {
        "x-umami-api-key" => api_key,
        "Accept" => "application/json"
      }
    elsif username.present? && password.present?
      token = fetch_or_refresh_token
      return nil if token.blank?

      {
        "Authorization" => "Bearer #{token}",
        "Accept" => "application/json"
      }
    else
      { "Accept" => "application/json" }
    end
  end

  def fetch_or_refresh_token
    Rails.cache.fetch("umami_auth_token_#{@base_url}", expires_in: 12.hours) do
      response = self.class.post(
        "#{@base_url}/api/auth/login",
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
        body: { username: username, password: password }.to_json,
        timeout: DEFAULT_TIMEOUT
      )

      if response.success?
        response.parsed_response["token"]
      else
        Rails.logger.error("[UmamiClient] Login failed: #{response.code} #{response.body}")
        nil
      end
    end
  rescue StandardError => e
    Rails.logger.error("[UmamiClient] Auth login exception: #{e.message}")
    nil
  end

  def parse_stats_response(data)
    return { visitors: 0, pageviews: 0, bounce_rate: 0 } unless data.is_a?(Hash)

    pageviews = extract_metric_value(data["pageviews"])
    visitors = extract_metric_value(data["visitors"])
    visits = extract_metric_value(data["visits"])
    bounces = extract_metric_value(data["bounces"])

    bounce_rate = if visits.positive?
                    ((bounces.to_f / visits) * 100).round
    else
                    0
    end

    {
      pageviews: pageviews,
      visitors: visitors,
      visits: visits,
      bounces: bounces,
      bounce_rate: bounce_rate
    }
  end

  def extract_metric_value(metric)
    if metric.is_a?(Hash)
      metric["value"].to_i
    elsif metric.is_a?(Numeric)
      metric.to_i
    else
      0
    end
  end

  def extract_host(url_or_domain)
    url_or_domain = url_or_domain.to_s.strip
    return "" if url_or_domain.blank?

    url_or_domain = "https://#{url_or_domain}" unless url_or_domain.start_with?("http://", "https://")
    URI.parse(url_or_domain).host || url_or_domain
  rescue URI::InvalidURIError
    url_or_domain
  end
end
