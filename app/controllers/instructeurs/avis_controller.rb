module Instructeurs
  class AvisController < InstructeurController
    include CreateAvisConcern

    A_DONNER_STATUS = 'a-donner'
    DONNES_STATUS   = 'donnes'

    def revoquer
      avis = Avis.find(params[:id])
      if avis.revoke_by!(current_instructeur)
        flash.notice = "#{avis.expert.email} ne peut plus donner son avis sur ce dossier."
        redirect_back(fallback_location: avis_instructeur_dossier_path(avis.procedure, avis.dossier))
      end
    end

    def revive
      avis = Avis.find(params[:id])
      if avis.revivable_by?(current_instructeur)
        if avis.answer.blank?
          AvisMailer.avis_invitation(avis).deliver_later
          flash.notice = "Un mail de relance a été envoyé à #{avis.expert.email}"
          redirect_back(fallback_location: avis_instructeur_dossier_path(avis.procedure, avis.dossier))
        else
          flash.alert = "#{avis.expert.email} a déjà donné son avis"
          redirect_back(fallback_location: avis_instructeur_dossier_path(avis.procedure, avis.dossier))
        end
      end
    end
  end
end
