# frozen_string_literal: true

class ProjectUmamiSyncService
  Result = Struct.new(:success?, :message, :stats, keyword_init: true)

  def self.call(project, client: UmamiClient.new)
    new(project, client: client).call
  end

  def initialize(project, client: UmamiClient.new)
    @project = project
    @client = client
  end

  def call
    # 1. Resolve Umami website ID if not set
    if @project.umami_website_id.blank?
      resolve_website_id
    end

    if @project.umami_website_id.blank?
      msg = "Aucun site Umami trouvé pour le domaine #{@project.production_url.presence || '(sans URL de production)'}"
      Rails.logger.error("event=umami_sync_failed project=#{@project.slug} error=#{msg.inspect}")
      @project.update_columns(umami_sync_error: msg)
      return Result.new(success?: false, message: msg)
    end

    # 2. Fetch 24h stats
    stats = @client.stats_24h(@project.umami_website_id)

    if stats[:error]
      Rails.logger.error("event=umami_sync_failed project=#{@project.slug} error=#{stats[:error].to_s.inspect}")
      @project.update_columns(umami_sync_error: stats[:error])
      Result.new(success?: false, message: stats[:error])
    else
      @project.update_columns(
        umami_visitors_24h: stats[:visitors] || 0,
        umami_pageviews_24h: stats[:pageviews] || 0,
        umami_bounce_rate: stats[:bounce_rate] || 0,
        umami_synced_at: Time.current,
        umami_sync_error: nil
      )
      Result.new(success?: true, message: "Synchronisé avec succès", stats: stats)
    end
  rescue StandardError => e
    Rails.logger.error("event=umami_sync_failed project=#{@project.slug} error=#{e.message.to_s.inspect}")
    @project.update_columns(umami_sync_error: e.message)
    Result.new(success?: false, message: e.message)
  end

  private

  def resolve_website_id
    return if @project.production_url.blank?

    site = @client.find_website_by_domain(@project.production_url)
    if site && site["id"].present?
      @project.update_column(:umami_website_id, site["id"])
    end
  end
end
