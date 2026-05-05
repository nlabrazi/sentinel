class PagesController < ApplicationController
  def deploys
    # On pourrait afficher les derniers déploiements de tous les projets
    @deployments = Deployment.includes(:project).order(created_at: :desc).limit(20)
  end

  def settings
    # Page placeholder pour les paramètres globaux
  end
end
