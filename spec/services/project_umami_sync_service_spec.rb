# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectUmamiSyncService, type: :service do
  let(:project) do
    create(
      :project,
      name: "Sawt AI",
      production_url: "https://sawt.example.com",
      umami_website_id: "site-uuid-1"
    )
  end
  let(:client) { instance_double(UmamiClient) }

  describe "#call" do
    it "fetches 24h stats and updates project attributes when website_id is present" do
      expect(client).to receive(:stats_24h).with("site-uuid-1").and_return(
        visitors: 450,
        pageviews: 1200,
        bounce_rate: 32,
        error: nil
      )

      result = described_class.call(project, client: client)

      expect(result.success?).to be true
      project.reload
      expect(project.umami_visitors_24h).to eq(450)
      expect(project.umami_pageviews_24h).to eq(1200)
      expect(project.umami_bounce_rate).to eq(32)
      expect(project.umami_synced_at).to be_present
      expect(project.umami_sync_error).to be_nil
    end

    it "resolves website_id automatically via domain when website_id is blank" do
      project.update!(umami_website_id: nil)

      expect(client).to receive(:find_website_by_domain).with(project.production_url).and_return(
        { "id" => "auto-detected-uuid", "domain" => "sawt.example.com" }
      )
      expect(client).to receive(:stats_24h).with("auto-detected-uuid").and_return(
        visitors: 100,
        pageviews: 300,
        bounce_rate: 15,
        error: nil
      )

      result = described_class.call(project, client: client)

      expect(result.success?).to be true
      project.reload
      expect(project.umami_website_id).to eq("auto-detected-uuid")
      expect(project.umami_visitors_24h).to eq(100)
      expect(project.umami_pageviews_24h).to eq(300)
    end

    it "records sync error when website cannot be resolved" do
      project.update!(umami_website_id: nil, production_url: "https://unknown.example.com")

      expect(client).to receive(:find_website_by_domain).with(project.production_url).and_return(nil)

      result = described_class.call(project, client: client)

      expect(result.success?).to be false
      project.reload
      expect(project.umami_sync_error).to include("Aucun site Umami trouvé")
    end

    it "records sync error when stats API returns an error" do
      expect(client).to receive(:stats_24h).with("site-uuid-1").and_return(
        error: "HTTP 500: Internal Server Error"
      )

      result = described_class.call(project, client: client)

      expect(result.success?).to be false
      project.reload
      expect(project.umami_sync_error).to eq("HTTP 500: Internal Server Error")
    end
  end
end
