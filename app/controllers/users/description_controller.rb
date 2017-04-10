class Users::DescriptionController < UsersController
  before_action only: [:show] do
    authorized_routes? self.class
  end

  before_action :check_autorisation_donnees, only: [:show]
  before_action :check_starter_dossier_informations, only: [:show]

  def show
    @dossier ||= current_user_dossier.decorate

    @procedure = @dossier.procedure
    @champs = @dossier.ordered_champs

    @headers = @champs.select { |c| c.type_champ == 'header_section' }

    unless @dossier.can_be_initiated?
      flash[:alert] = t('errors.messages.procedure_archived')
    end

  rescue ActiveRecord::RecordNotFound
    flash.alert = t('errors.messages.dossier_not_found')
    redirect_to url_for(root_path)
  end

  def update
    dossier = current_user_dossier
    procedure = dossier.procedure

    return head :forbidden unless dossier.can_be_initiated?

    @champs = dossier.ordered_champs

    check_mandatory_fields = !draft_submission?

    if params[:champs]
      champs_service_errors = ChampsService.save_champs dossier.champs,
                                                        params,
                                                        check_mandatory_fields

      return redirect_to_description_with_errors(dossier, champs_service_errors) if champs_service_errors.any?
    end

    if procedure.cerfa_flag? && params[:cerfa_pdf]
      cerfa = Cerfa.new(content: params[:cerfa_pdf], dossier: dossier, user: current_user)
      return redirect_to_description_with_errors(dossier, cerfa.errors.full_messages) unless cerfa.save
    end

    errors_upload = PiecesJustificativesService.upload!(dossier, current_user, params)
    return redirect_to_description_with_errors(dossier, errors_upload) if errors_upload.any?

    if draft_submission?
      flash.notice = 'Votre brouillon a bien été sauvegardé.'
      redirect_to url_for(controller: :dossiers, action: :index, liste: :brouillon)
    else
      if dossier.draft?
        dossier.initiated!
        NotificationMailer.send_notification(dossier, procedure.initiated_mail).deliver_now!
      end
      flash.notice = 'Félicitations, votre demande a bien été enregistrée.'
      redirect_to url_for(controller: :recapitulatif, action: :show, dossier_id: dossier.id)
    end
  end

  def pieces_justificatives
    invite = current_user.invite? params[:dossier_id]

    @dossier ||= Dossier.find(params[:dossier_id]) if invite
    @dossier ||= current_user_dossier

    if @dossier.procedure.cerfa_flag?
      unless params[:cerfa_pdf].nil?
        cerfa = Cerfa.new(content: params[:cerfa_pdf], dossier: @dossier, user: current_user)
        unless cerfa.save
          flash.alert = cerfa.errors.full_messages.join('<br />').html_safe
        end
      end
    end

    if !((errors_upload = PiecesJustificativesService.upload!(@dossier, current_user, params)).empty?)
      if flash.alert.nil?
        flash.alert = errors_upload.join('<br>').html_safe
      else
        flash.alert = (flash.alert + '<br />' + errors_upload.join('<br>').html_safe).html_safe
      end

    else
      flash.notice = 'Nouveaux fichiers envoyés' if flash.alert.nil?
      @dossier.next_step! 'user', 'update'
    end

    return redirect_to users_dossiers_invite_path(id: current_user.invites.find_by_dossier_id(@dossier.id).id) if invite

    redirect_to users_dossier_recapitulatif_path
  end

  def self.route_authorization
    {
        states: [:draft, :initiated, :replied, :updated]
    }
  end

  private

  def redirect_to_description_with_errors(dossier, errors)
    flash.alert = errors.join('<br>').html_safe
    redirect_to users_dossier_description_path(dossier_id: dossier.id)
  end

  def draft_submission?
    params[:submit] && params[:submit].keys.first == 'brouillon'
  end

  def check_autorisation_donnees
    @dossier = current_user_dossier

    redirect_to url_for(users_dossier_path(@dossier.id)) if @dossier.autorisation_donnees.nil? || !@dossier.autorisation_donnees
  end

  def check_starter_dossier_informations
    @dossier ||= current_user_dossier

    if (@dossier.procedure.for_individual? && @dossier.individual.nil?) ||
        (!@dossier.procedure.for_individual? && @dossier.entreprise.nil?)
      redirect_to url_for(users_dossier_path(@dossier.id))
    end
  end
end
