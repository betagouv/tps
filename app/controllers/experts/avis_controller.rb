module Experts
  class AvisController < ExpertController
    include CreateAvisConcern

    before_action :authenticate_expert!, except: [:sign_up, :update_expert]
    before_action :check_if_avis_revoked, only: [:show]
    before_action :redirect_if_no_sign_up_needed, only: [:sign_up]
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

    def create_avis
      @procedure = Procedure.find(params[:procedure_id])
      if !@procedure.feature_enabled?(:expert_not_allowed_to_invite)
        @new_avis = create_avis_from_params(avis.dossier, current_expert, avis.confidentiel)

        if @new_avis.nil?
          redirect_to instruction_expert_avis_path(avis.procedure, avis)
        else
          set_avis_and_dossier
          render :instruction
        end
      else
        flash.alert = "Cette démarche ne vous permet pas de demander un avis externe"
        redirect_to instruction_expert_avis_path(avis.procedure, avis)
      end
    end

    def update
      if @avis.update(avis_params)
        flash.notice = 'Votre réponse est enregistrée.'
        @avis.dossier.update!(last_avis_updated_at: Time.zone.now)
        redirect_to instruction_expert_avis_path(@avis.procedure, @avis)
      else
        flash.now.alert = @avis.errors.full_messages
        @new_avis = Avis.new
        render :instruction
      end
    end

    def sign_up
      @email = params[:email]
      @dossier = Avis.includes(:dossier).find(params[:id]).dossier

      render
    end

    def update_expert
      procedure_id = params[:procedure_id]
      avis_id = params[:id]
      email = params[:email]
      password = params[:user][:password]

      # Not perfect because the password will not be changed if the user already exists
      user = User.create_or_promote_to_expert(email, password)

      if user.valid?
        sign_in(user)

        redirect_to url_for(expert_all_avis_path)
      else
        flash[:alert] = user.errors.full_messages
        redirect_to url_for(sign_up_expert_avis_path(procedure_id, avis_id, email))
      end
    end

    def messagerie
      @commentaire = Commentaire.new
    end

    def create_commentaire
      @commentaire = CommentaireService.build(current_expert, avis.dossier, commentaire_params)

      if @commentaire.save
        @commentaire.dossier.update!(last_commentaire_updated_at: Time.zone.now)
        flash.notice = "Message envoyé"
        redirect_to messagerie_expert_avis_path(avis.procedure, avis)
      else
        flash.alert = @commentaire.errors.full_messages
        render :messagerie
      end
    end

    def bilans_bdf
      if avis.dossier.etablissement&.entreprise_bilans_bdf.present?
        extension = params[:format]
        render extension.to_sym => avis.dossier.etablissement.entreprise_bilans_bdf_to_sheet(extension)
      else
        redirect_to instructeur_avis_path(avis)
      end
    end

    private

    def redirect_if_no_sign_up_needed
      avis = Avis.find(params[:id])

      if current_expert.present?
        # an expert is authenticated ... lets see if it can view the dossier

        redirect_to expert_avis_url(avis.procedure, avis)

      elsif avis.expert&.email == params[:email] && avis.expert.user.active?.present?

        redirect_to new_user_session_url
      end
    end

    def avis
      current_expert.avis.includes(dossier: [:avis, :commentaires]).find(params[:id])
    end

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

    def avis_params
      params.require(:avis).permit(:answer, :piece_justificative_file)
    end

    def commentaire_params
      params.require(:commentaire).permit(:body, :piece_jointe)
    end
  end
end
