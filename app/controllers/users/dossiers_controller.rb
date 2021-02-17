module Users
  class DossiersController < UserController
    include DossierHelper

    layout 'procedure_context', only: [:identite, :update_identite, :siret, :update_siret]

    ACTIONS_ALLOWED_TO_ANY_USER = [:index, :recherche, :new]
    ACTIONS_ALLOWED_TO_OWNER_OR_INVITE = [:show, :demande, :messagerie, :brouillon, :update_brouillon, :modifier, :update, :create_commentaire]

    before_action :ensure_ownership!, except: ACTIONS_ALLOWED_TO_ANY_USER + ACTIONS_ALLOWED_TO_OWNER_OR_INVITE
    before_action :ensure_ownership_or_invitation!, only: ACTIONS_ALLOWED_TO_OWNER_OR_INVITE
    before_action :ensure_dossier_can_be_updated, only: [:update_identite, :update_brouillon, :modifier, :update]
    before_action :forbid_invite_submission!, only: [:update_brouillon]
    before_action :forbid_closed_submission!, only: [:update_brouillon]
    before_action :show_demarche_en_test_banner
    before_action :store_user_location!, only: :new

    def index
      @user_dossiers = current_user.dossiers.includes(:procedure).order_by_updated_at.page(page)
      @dossiers_invites = current_user.dossiers_invites.includes(:procedure).order_by_updated_at.page(page)
      @dossiers_supprimes = current_user.deleted_dossiers.order_by_updated_at.page(page)
      @statut = statut(@user_dossiers, @dossiers_invites, @dossiers_supprimes, params[:statut])
    end

    def show
      if dossier.brouillon?
        redirect_to brouillon_dossier_path(dossier)
        return
      end

      @dossier = dossier
      respond_to do |format|
        format.pdf do
          @include_infos_administration = false
          render(template: 'dossiers/show', formats: [:pdf])
        end
        format.all
      end
    end

    def demande
      @dossier = dossier
    end

    def messagerie
      @dossier = dossier
      @commentaire = Commentaire.new
    end

    def attestation
      if dossier.attestation&.pdf&.attached?
        redirect_to dossier.attestation.pdf.service_url
      else
        flash.notice = "L'attestation n'est plus disponible sur ce dossier."
        redirect_to dossier_path(dossier)
      end
    end

    def identite
      @dossier = dossier
      @user = current_user
    end

    def update_identite
      @dossier = dossier

      if @dossier.individual.update(individual_params)
        @dossier.update!(autorisation_donnees: true)
        flash.notice = "Identité enregistrée"

        redirect_to brouillon_dossier_path(@dossier)
      else
        flash.now.alert = @dossier.individual.errors.full_messages
        render :identite
      end
    end

    def siret
      @dossier = dossier
    end

    def update_siret
      @dossier = dossier

      # We use the user as the holder model object for the siret value
      # (so that we can restore it on the form in case of error).
      #
      # This is the only remaining use of User#siret: it could be refactored away.
      # However some existing users have a siret but no associated etablissement,
      # so we would need to analyze the legacy data and decide what to do with it.
      current_user.siret = siret_params[:siret]

      siret_model = Siret.new(siret: siret_params[:siret])
      if !siret_model.valid?
        return render_siret_error(siret_model.errors.full_messages)
      end

      sanitized_siret = siret_model.siret
      begin
        etablissement = APIEntrepriseService.create_etablissement(@dossier, sanitized_siret, current_user.id)
      rescue APIEntreprise::API::Error::RequestFailed, APIEntreprise::API::Error::BadGateway, APIEntreprise::API::Error::TimedOut
        return render_siret_error(t('errors.messages.siret_network_error'))
      end
      if etablissement.nil?
        return render_siret_error(t('errors.messages.siret_unknown'))
      end

      current_user.update!(siret: sanitized_siret)
      @dossier.update!(autorisation_donnees: true)

      redirect_to etablissement_dossier_path
    end

    def etablissement
      @dossier = dossier

      # Redirect if the user attempts to access the page URL directly
      if !@dossier.etablissement
        flash.alert = 'Aucun établissement n’est associé à ce dossier'
        return redirect_to siret_dossier_path(@dossier)
      end
    end

    def brouillon
      @dossier = dossier_with_champs

      # TODO: remove when the champs are unifed
      if !@dossier.autorisation_donnees
        if dossier.procedure.for_individual
          redirect_to identite_dossier_path(@dossier)
        else
          redirect_to siret_dossier_path(@dossier)
        end
      end
    end

    # FIXME:
    # - delegate draft save logic to champ ?
    def update_brouillon
      @dossier = dossier_with_champs

      errors = update_dossier_and_compute_errors

      if passage_en_construction? && errors.blank?
        @dossier.passer_en_construction!
        NotificationMailer.send_initiated_notification(@dossier).deliver_later
        @dossier.groupe_instructeur.instructeurs.with_instant_email_dossier_notifications.each do |instructeur|
          DossierMailer.notify_new_dossier_depose_to_instructeur(@dossier, instructeur.email).deliver_later
        end
        return redirect_to(merci_dossier_path(@dossier))
      elsif errors.present?
        flash.now.alert = errors
      else
        flash.now.notice = 'Votre brouillon a bien été sauvegardé.'
      end

      respond_to do |format|
        format.html { render :brouillon }
        format.js { render :brouillon }
      end
    end

    def extend_conservation
      dossier.update(en_construction_conservation_extension: dossier.en_construction_conservation_extension + 1.month)
      flash[:notice] = 'Votre dossier sera conservé un mois supplémentaire'
      redirect_to dossier_path(@dossier)
    end

    def modifier
      @dossier = dossier_with_champs
    end

    def update
      @dossier = dossier_with_champs

      errors = update_dossier_and_compute_errors

      if errors.present?
        flash.now.alert = errors
        render :modifier
      else
        redirect_to demande_dossier_path(@dossier)
      end
    end

    def merci
      @dossier = current_user.dossiers.includes(:procedure).find(params[:id])
    end

    def create_commentaire
      @commentaire = CommentaireService.build(current_user, dossier, commentaire_params)

      if @commentaire.save
        @commentaire.dossier.update!(last_commentaire_updated_at: Time.zone.now)
        dossier.followers_instructeurs
          .with_instant_email_message_notifications
          .each do |instructeur|
          DossierMailer.notify_new_commentaire_to_instructeur(dossier, instructeur.email).deliver_later
        end
        flash.notice = "Votre message a bien été envoyé à l’instructeur en charge de votre dossier."
        redirect_to messagerie_dossier_path(dossier)
      else
        flash.now.alert = @commentaire.errors.full_messages
        render :messagerie
      end
    end

    def ask_deletion
      dossier = current_user.dossiers.includes(:user, procedure: :administrateurs).find(params[:id])

      if dossier.can_be_deleted_by_user?
        dossier.discard_and_keep_track!(current_user, :user_request)
        flash.notice = 'Votre dossier a bien été supprimé.'
        redirect_to dossiers_path
      else
        flash.notice = "L'instruction de votre dossier a commencé, il n'est plus possible de supprimer votre dossier. Si vous souhaitez annuler l'instruction contactez votre administration par la messagerie de votre dossier."
        redirect_to dossier_path(dossier)
      end
    end

    def recherche
      @search_terms = params[:q]
      return redirect_to dossiers_path if @search_terms.blank?

      @dossiers = DossierSearchService.matching_dossiers_for_user(@search_terms, current_user).page(page)

      if @dossiers.present?
        # we need the page condition when accessing page n with n>1 when the page has only 1 result
        # in order to avoid an unpleasant redirection when changing page
        if @dossiers.count == 1 && page == 1
          redirect_to url_for_dossier(@dossiers.first)
        else
          render :index
        end
      else
        flash.alert = "Vous n’avez pas de dossiers contenant « #{@search_terms} »."
        redirect_to dossiers_path
      end
    end

    def new
      erase_user_location!

      begin
        if params[:brouillon]
          procedure = Procedure.brouillon.find(params[:procedure_id])
        else
          procedure = Procedure.publiees.find(params[:procedure_id])
        end
      rescue ActiveRecord::RecordNotFound
        flash.alert = t('errors.messages.procedure_not_found')
        return redirect_to url_for dossiers_path
      end

      dossier = Dossier.new(
        revision: procedure.active_revision,
        groupe_instructeur: procedure.defaut_groupe_instructeur_for_new_dossier,
        user: current_user,
        state: Dossier.states.fetch(:brouillon)
      )
      dossier.build_default_individual
      dossier.save!

      if dossier.procedure.for_individual
        redirect_to identite_dossier_path(dossier)
      else
        redirect_to siret_dossier_path(id: dossier.id)
      end
    end

    def dossier_for_help
      dossier_id = params[:id] || params[:dossier_id]
      @dossier || (dossier_id.present? && Dossier.find_by(id: dossier_id.to_i))
    end

    private

    # if the status tab is filled, then this tab
    # else first filled tab
    # else mes-dossiers
    def statut(mes_dossiers, dossiers_invites, dossiers_supprimes, params_statut)
      tabs = {
        'mes-dossiers' => mes_dossiers.present?,
        'dossiers-invites' => dossiers_invites.present?,
        'dossiers-supprimes' => dossiers_supprimes.present?
      }
      if tabs[params_statut]
        params_statut
      else
        tabs
          .filter { |_tab, filled| filled }
          .map { |tab, _| tab }
          .first || 'mes-dossiers'
      end
    end

    def store_user_location!
      store_location_for(:user, request.fullpath)
    end

    def erase_user_location!
      clear_stored_location_for(:user)
    end

    def show_demarche_en_test_banner
      if @dossier.present? && @dossier.procedure.brouillon?
        flash.now.alert = "Ce dossier est déposé sur une démarche en test. Toute modification de la démarche par l'administrateur (ajout d'un champ, publication de la démarche...) entraînera sa suppression."
      end
    end

    def ensure_dossier_can_be_updated
      if !dossier.can_be_updated_by_user?
        flash.alert = 'Votre dossier ne peut plus être modifié'
        redirect_to dossiers_path
      end
    end

    def page
      [params[:page].to_i, 1].max
    end

    # FIXME: require(:dossier) when all the champs are united
    def champs_params
      params.permit(dossier: {
        champs_attributes: [
          :id, :value, :external_id, :primary_value, :secondary_value, :piece_justificative_file, value: [],
          champs_attributes: [:id, :_destroy, :value, :external_id, :primary_value, :secondary_value, :piece_justificative_file, value: []]
        ]
      })
    end

    def dossier
      @dossier ||= Dossier.find(params[:id] || params[:dossier_id])
    end

    def dossier_with_champs
      Dossier.with_champs.find(params[:id])
    end

    def change_groupe_instructeur?
      if params[:dossier].key?(:groupe_instructeur_id)
        groupe_instructeur_id = params[:dossier][:groupe_instructeur_id]
        if groupe_instructeur_id.nil?
          @dossier.groupe_instructeur_id.present?
        else
          @dossier.groupe_instructeur_id != groupe_instructeur_id.to_i
        end
      end
    end

    def groupe_instructeur_from_params
      groupe_instructeur_id = params[:dossier][:groupe_instructeur_id]
      if groupe_instructeur_id.present?
        @dossier.procedure.groupe_instructeurs.find(groupe_instructeur_id)
      end
    end

    def update_dossier_and_compute_errors
      errors = []

      if champs_params[:dossier]
        @dossier.assign_attributes(champs_params[:dossier])
        # FIXME in some cases a removed repetition bloc row is submitted.
        # In this case it will be trated as a new records and action will fail.
        @dossier.champs.filter(&:repetition?).each do |champ|
          champ.champs = champ.champs.filter(&:persisted?)
        end
        if @dossier.champs.any?(&:changed?)
          @dossier.last_champ_updated_at = Time.zone.now
        end
        if !@dossier.save
          errors += @dossier.errors.full_messages
        elsif change_groupe_instructeur?
          @dossier.assign_to_groupe_instructeur(groupe_instructeur_from_params)
        end
      end

      if !save_draft?
        errors += @dossier.check_mandatory_champs

        if @dossier.groupe_instructeur.nil?
          errors << "Le champ « #{@dossier.procedure.routing_criteria_name} » doit être rempli"
        end
      end

      errors
    end

    def ensure_ownership!
      if !current_user.owns?(dossier)
        forbidden!
      end
    end

    def ensure_ownership_or_invitation!
      if !current_user.owns_or_invite?(dossier)
        forbidden!
      end
    end

    def forbid_invite_submission!
      if passage_en_construction? && !current_user.owns?(dossier)
        forbidden!
      end
    end

    def forbid_closed_submission!
      if passage_en_construction? && !dossier.can_transition_to_en_construction?
        forbidden!
      end
    end

    def forbidden!
      flash[:alert] = "Vous n'avez pas accès à ce dossier"
      redirect_to root_path
    end

    def render_siret_error(error_message)
      flash.alert = error_message
      render :siret
    end

    def individual_params
      params.require(:individual).permit(:gender, :nom, :prenom, :birthdate)
    end

    def siret_params
      params.require(:user).permit(:siret)
    end

    def commentaire_params
      params.require(:commentaire).permit(:body, :piece_jointe)
    end

    def passage_en_construction?
      dossier.brouillon? && !save_draft?
    end

    def save_draft?
      dossier.brouillon? && !params[:submit_draft]
    end
  end
end
