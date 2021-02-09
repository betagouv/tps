module Experts
  class AvisController < ExpertController
    include CreateAvisConcern

    before_action :authenticate_expert!, except: [:sign_up, :create_instructeur]
    before_action :check_if_avis_revoked, only: [:show]
    before_action :redirect_if_no_sign_up_needed, only: [:sign_up]
    before_action :check_avis_exists_and_email_belongs_to_avis, only: [:sign_up, :create_instructeur]
    before_action :set_avis_and_dossier, only: [:show, :instruction, :messagerie, :create_commentaire, :update]

    A_DONNER_STATUS = 'a-donner'
    DONNES_STATUS   = 'donnes'

    def index
      avis = current_expert.avis.includes(dossier: [groupe_instructeur: :procedure])
      @avis_by_procedure = avis.to_a.group_by(&:procedure)
    end

    def procedure
      @procedure = Procedure.find(params[:procedure_id])
      expert_avis = current_expert.avis.includes(:dossier).where(dossiers: { groupe_instructeur: GroupeInstructeur.where(procedure: @procedure.id) })
      @avis_a_donner = expert_avis.without_answer
      @avis_donnes = expert_avis.with_answer

      @statut = params[:statut].presence || A_DONNER_STATUS

      @avis = case @statut
      when A_DONNER_STATUS
        @avis_a_donner
      when DONNES_STATUS
        @avis_donnes
      end

      @avis = @avis.page([params[:page].to_i, 1].max)
    end

    def show
    end

    def instruction
      @new_avis = Avis.new
    end

    private

    def check_if_avis_revoked
      avis = Avis.find(params[:id])
      if avis.revoked?
        flash.alert = "Vous n'avez plus accès à ce dossier."
        redirect_to url_for(root_path)
      end
    end

    def set_avis_and_dossier
      @avis = Avis.find(params[:id])
      @dossier = @avis.dossier
    end
  end
end