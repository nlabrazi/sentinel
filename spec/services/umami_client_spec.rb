# frozen_string_literal: true

require "rails_helper"

RSpec.describe UmamiClient, type: :service do
  let(:base_url) { "https://umami.example.com" }
  let(:client) { described_class.new(base_url: base_url) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("UMAMI_BASE_URL").and_return(base_url)
    allow(ENV).to receive(:[]).with("UMAMI_AUTH_TOKEN").and_return(nil)
  end

  describe "#configured?" do
    it "returns true when UMAMI_AUTH_TOKEN is present" do
      allow(ENV).to receive(:[]).with("UMAMI_AUTH_TOKEN").and_return("jwt-token-xyz")
      expect(client.configured?).to be true
    end

    it "returns true when UMAMI_API_KEY is present" do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return("test-key")
      expect(client.configured?).to be true
    end

    it "returns true when UMAMI_USERNAME and UMAMI_PASSWORD are present" do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_AUTH_TOKEN").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_USERNAME").and_return("admin")
      allow(ENV).to receive(:[]).with("UMAMI_PASSWORD").and_return("secret")
      expect(client.configured?).to be true
    end

    it "returns false when no credentials are configured" do
      allow(ENV).to receive(:[]).with("UMAMI_AUTH_TOKEN").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_USERNAME").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_PASSWORD").and_return(nil)
      expect(client.configured?).to be false
    end
  end

  describe "#websites" do
    before do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return("test-api-key")
    end

    it "returns an array of websites from Umami API" do
      stub_request(:get, "#{base_url}/api/websites")
        .with(headers: { "x-umami-api-key" => "test-api-key" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            data: [
              { id: "site-1", name: "Sawt AI", domain: "sawt.example.com" },
              { id: "site-2", name: "Media Tools", domain: "media.example.com" }
            ]
          }.to_json
        )

      websites = client.websites
      expect(websites.size).to eq(2)
      expect(websites.first["id"]).to eq("site-1")
      expect(websites.first["domain"]).to eq("sawt.example.com")
    end

    it "handles token login when username and password are provided" do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_USERNAME").and_return("admin")
      allow(ENV).to receive(:[]).with("UMAMI_PASSWORD").and_return("secret")

      stub_request(:post, "#{base_url}/api/auth/login")
        .with(body: { username: "admin", password: "secret" }.to_json)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { token: "jwt-token-123" }.to_json
        )

      stub_request(:get, "#{base_url}/api/websites")
        .with(headers: { "Authorization" => "Bearer jwt-token-123" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: [
            { id: "site-1", name: "Sawt AI", domain: "sawt.example.com" }
          ].to_json
        )

      websites = client.websites
      expect(websites.size).to eq(1)
      expect(websites.first["id"]).to eq("site-1")
    end

    it "uses UMAMI_AUTH_TOKEN directly without calling login" do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return(nil)
      allow(ENV).to receive(:[]).with("UMAMI_AUTH_TOKEN").and_return("direct-jwt-token")

      stub_request(:get, "#{base_url}/api/websites")
        .with(headers: { "Authorization" => "Bearer direct-jwt-token" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: [
            { id: "site-token", name: "Token App", domain: "token.example.com" }
          ].to_json
        )

      websites = client.websites
      expect(websites.size).to eq(1)
      expect(websites.first["id"]).to eq("site-token")
    end
  end

  describe "#find_website_by_domain" do
    before do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return("test-api-key")
      stub_request(:get, "#{base_url}/api/websites")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: [
            { id: "site-uuid-1", name: "Sawt AI", domain: "sawt.example.com" },
            { id: "site-uuid-2", name: "Media Tools", domain: "https://media.example.com" }
          ].to_json
        )
    end

    it "finds website by exact domain" do
      site = client.find_website_by_domain("sawt.example.com")
      expect(site).to be_present
      expect(site["id"]).to eq("site-uuid-1")
    end

    it "finds website by full production URL" do
      site = client.find_website_by_domain("https://sawt.example.com/login")
      expect(site).to be_present
      expect(site["id"]).to eq("site-uuid-1")
    end

    it "returns nil when domain is not found" do
      site = client.find_website_by_domain("https://other.example.com")
      expect(site).to be_nil
    end
  end

  describe "#stats" do
    before do
      allow(ENV).to receive(:[]).with("UMAMI_API_KEY").and_return("test-api-key")
    end

    it "returns parsed stats and calculates bounce rate" do
      stub_request(:get, %r{#{base_url}/api/websites/site-uuid-1/stats})
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            pageviews: { value: 1250, change: 100 },
            visitors: { value: 430, change: 20 },
            visits: { value: 500, change: 30 },
            bounces: { value: 125, change: -10 },
            totaltime: { value: 45000, change: 500 }
          }.to_json
        )

      stats = client.stats("site-uuid-1", start_at: 1000, end_at: 2000)
      expect(stats[:pageviews]).to eq(1250)
      expect(stats[:visitors]).to eq(430)
      expect(stats[:visits]).to eq(500)
      expect(stats[:bounces]).to eq(125)
      expect(stats[:bounce_rate]).to eq(25) # (125 / 500) * 100
      expect(stats[:error]).to be_nil
    end

    it "returns error hash when API request fails" do
      stub_request(:get, %r{#{base_url}/api/websites/site-uuid-1/stats})
        .to_return(status: 404, body: "Not found")

      stats = client.stats("site-uuid-1", start_at: 1000, end_at: 2000)
      expect(stats[:error]).to include("HTTP 404")
    end
  end
end
