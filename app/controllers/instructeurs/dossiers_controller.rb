module Instructeurs
  class DossiersController < ProceduresController
    include ActionView::Helpers::NumberHelper
    include ActionView::Helpers::TextHelper
    include CreateAvisConcern
    include DossierHelper

    include ActionController::Streaming
    include Zipline

    after_action :mark_demande_as_read, only: :show
    after_action :mark_messagerie_as_read, only: [:messagerie, :create_commentaire]
    after_action :mark_avis_as_read, only: [:avis, :create_avis]
    after_action :mark_annotations_privees_as_read, only: [:annotations_privees, :update_annotations]

    def attestation
      if dossier.attestation.pdf.attached?
        redirect_to dossier.attestation.pdf.service_url
      end
    end

    def geo_data
      send_data dossier.to_feature_collection.to_json,
        type: 'application/json',
        filename: "dossier-#{dossier.id}-features.json"
    end

    def apercu_attestation
      @attestation = dossier.procedure.attestation_template.render_attributes_for(dossier: dossier)

      render 'new_administrateur/attestation_templates/show', formats: [:pdf]
    end

    def bilans_bdf
      extension = params[:format]
      render extension.to_sym => dossier.etablissement.entreprise_bilans_bdf_to_sheet(extension)
    end

    def show
      @demande_seen_at = current_instructeur.follows.find_by(dossier: dossier)&.demande_seen_at

      respond_to do |format|
        format.pdf do
          @include_infos_administration = true
          render(file: 'dossiers/show', formats: [:pdf])
        end
        format.all
      end
    end

    def messagerie
      @commentaire = Commentaire.new
      @messagerie_seen_at = current_instructeur.follows.find_by(dossier: dossier)&.messagerie_seen_at
    end

    def annotations_privees
      @annotations_privees_seen_at = current_instructeur.follows.find_by(dossier: dossier)&.annotations_privees_seen_at
    end

    def avis
      @avis_seen_at = current_instructeur.follows.find_by(dossier: dossier)&.avis_seen_at
      @avis = Avis.new
    end

    def personnes_impliquees
      @following_instructeurs_emails = dossier.followers_instructeurs.map(&:email)
      previous_followers = dossier.previous_followers_instructeurs - dossier.followers_instructeurs
      @previous_following_instructeurs_emails = previous_followers.map(&:email)
      @avis_emails = dossier.experts.map(&:email)
      @invites_emails = dossier.invites.map(&:email)
      @potential_recipients = dossier.groupe_instructeur.instructeurs.reject { |g| g == current_instructeur }
    end

    def send_to_instructeurs
      recipients = params['recipients'].presence || [].to_json
      recipients = Instructeur.find(JSON.parse(recipients))

      recipients.each do |recipient|
        recipient.follow(dossier)
        InstructeurMailer.send_dossier(current_instructeur, dossier, recipient).deliver_later
      end

      flash.notice = "Dossier envoyé"
      redirect_to(personnes_impliquees_instructeur_dossier_path(procedure, dossier))
    end

    def follow
      current_instructeur.follow(dossier)
      flash.notice = 'Dossier suivi'
      redirect_back(fallback_location: instructeur_procedures_url)
    end

    def unfollow
      current_instructeur.unfollow(dossier)
      flash.notice = "Vous ne suivez plus le dossier nº #{dossier.id}"

      redirect_back(fallback_location: instructeur_procedures_url)
    end

    def archive
      dossier.archiver!(current_instructeur)
      redirect_back(fallback_location: instructeur_procedures_url)
    end

    def unarchive
      dossier.desarchiver!(current_instructeur)
      redirect_back(fallback_location: instructeur_procedures_url)
    end

    def passer_en_instruction
      begin
        dossier.passer_en_instruction!(current_instructeur)
        flash.notice = 'Dossier passé en instruction.'
      rescue AASM::InvalidTransition => e
        flash.alert = aasm_error_message(e, target_state: :en_instruction)
      end

      render partial: 'state_button_refresh', locals: { dossier: dossier }
    end

    def repasser_en_construction
      begin
        dossier.repasser_en_construction!(current_instructeur)
        flash.notice = 'Dossier repassé en construction.'
      rescue AASM::InvalidTransition => e
        flash.alert = aasm_error_message(e, target_state: :en_construction)
      end

      render partial: 'state_button_refresh', locals: { dossier: dossier }
    end

    def repasser_en_instruction
      begin
        flash.notice = "Le dossier #{dossier.id} a été repassé en instruction."
        dossier.repasser_en_instruction!(current_instructeur)
      rescue AASM::InvalidTransition => e
        flash.alert = aasm_error_message(e, target_state: :en_instruction)
      end

      render partial: 'state_button_refresh', locals: { dossier: dossier }
    end

    def terminer
      motivation = params[:dossier] && params[:dossier][:motivation]
      justificatif = params[:dossier] && params[:dossier][:justificatif_motivation]

      begin
        case params[:process_action]
        when "refuser"
          target_state = :refuse
          dossier.refuser!(current_instructeur, motivation, justificatif)
          flash.notice = "Dossier considéré comme refusé."
        when "classer_sans_suite"
          target_state = :sans_suite
          dossier.classer_sans_suite!(current_instructeur, motivation, justificatif)
          flash.notice = "Dossier considéré comme sans suite."
        when "accepter"
          target_state = :accepte
          dossier.accepter!(current_instructeur, motivation, justificatif)
          flash.notice = "Dossier traité avec succès."
        end
      rescue AASM::InvalidTransition => e
        flash.alert = aasm_error_message(e, target_state: target_state)
      end

      render partial: 'state_button_refresh', locals: { dossier: dossier }
    end

    def create_commentaire
      @commentaire = CommentaireService.build(current_instructeur, dossier, commentaire_params)

      if @commentaire.save
        @commentaire.dossier.update!(last_commentaire_updated_at: Time.zone.now)
        current_instructeur.follow(dossier)
        flash.notice = "Message envoyé"
        redirect_to messagerie_instructeur_dossier_path(procedure, dossier)
      else
        flash.alert = @commentaire.errors.full_messages
        render :messagerie
      end
    end

    def create_avis
      @avis = create_avis_from_params(dossier, current_instructeur)

      if @avis.nil?
        redirect_to avis_instructeur_dossier_path(procedure, dossier)
      else
        @avis_seen_at = current_instructeur.follows.find_by(dossier: dossier)&.avis_seen_at
        render :avis
      end
    end

    def update_annotations
      dossier = current_instructeur.dossiers.includes(champs_private: :type_de_champ).find(params[:dossier_id])
      dossier.assign_attributes(champs_private_params)
      if dossier.champs_private.any?(&:changed?)
        dossier.last_champ_private_updated_at = Time.zone.now
      end
      dossier.save
      dossier.log_modifier_annotations!(current_instructeur)
      redirect_to annotations_privees_instructeur_dossier_path(procedure, dossier)
    end

    def print
      @dossier = dossier
      render layout: "print"
    end

    def telecharger_pjs
      return head(:forbidden) if !dossier.attachments_downloadable?

      generate_pdf_for_instructeur_export
      files = ActiveStorage::DownloadableFile.create_list_from_dossier(dossier)

      zipline(files, "dossier-#{dossier.id}.zip")
    end

    def delete_dossier
      if dossier.termine?
        dossier.discard_and_keep_track!(current_instructeur, :instructeur_request)
        flash.notice = 'Le dossier a bien été supprimé'
        redirect_to instructeur_procedure_path(procedure)
      else
        flash.alert = "Suppression impossible : le dossier n'est pas terminé"
        redirect_back(fallback_location: instructeur_procedures_url)
      end
    end

    private

    def dossier
      @dossier ||= current_instructeur.dossiers.find(params[:dossier_id])
    end

    def generate_pdf_for_instructeur_export
      @include_infos_administration = true
      pdf = render_to_string(file: 'dossiers/show', formats: [:pdf])
      dossier.pdf_export_for_instructeur.attach(io: StringIO.open(pdf), filename: "export-#{dossier.id}.pdf", content_type: 'application/pdf')
    end

    def commentaire_params
      params.require(:commentaire).permit(:body, :piece_jointe)
    end

    def champs_private_params
      params.require(:dossier).permit(champs_private_attributes: [
        :id, :primary_value, :secondary_value, :piece_justificative_file, :value, value: [],
        champs_attributes: [:id, :_destroy, :value, :primary_value, :secondary_value, :piece_justificative_file, value: []]
      ])
    end

    def mark_demande_as_read
      current_instructeur.mark_tab_as_seen(dossier, :demande)
    end

    def mark_messagerie_as_read
      current_instructeur.mark_tab_as_seen(dossier, :messagerie)
    end

    def mark_avis_as_read
      current_instructeur.mark_tab_as_seen(dossier, :avis)
    end

    def mark_annotations_privees_as_read
      current_instructeur.mark_tab_as_seen(dossier, :annotations_privees)
    end

    def aasm_error_message(exception, target_state:)
      if exception.originating_state == target_state
        "Le dossier est déjà #{dossier_display_state(target_state, lower: true)}."
      else
        "Le dossier est en ce moment #{dossier_display_state(exception.originating_state, lower: true)} : il n’est pas possible de le passer #{dossier_display_state(target_state, lower: true)}."
      end
    end
  end
end
