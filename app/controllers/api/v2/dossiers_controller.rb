class API::V2::DossiersController < API::V2::BaseController
  before_action :ensure_dossier_present

  def pdf
    @include_infos_administration = true
    render(template: 'dossiers/show', formats: [:pdf])
  end

  def geojson
    send_data dossier.to_feature_collection.to_json,
      type: 'application/json',
      filename: "dossier-#{dossier.id}-features.json"
  end

  private

  def ensure_dossier_present
    if dossier.blank?
      head :unauthorized
    end
  end

  def dossier
    @dossier ||= GlobalID::Locator.locate_signed(params[:id].to_s, for: 'api_v2')
  end
end
