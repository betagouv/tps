class ApplicationController < ActionController::Base
  include TrustedDeviceConcern
  include Pundit
  include Devise::StoreLocationExtension

  MAINTENANCE_MESSAGE = 'Le site est actuellement en maintenance. Il sera à nouveau disponible dans un court instant.'

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception, if: -> { !Rails.env.test? }
  before_action :set_current_roles
  before_action :set_sentry_user
  before_action :redirect_if_untrusted
  before_action :reject, if: -> { feature_enabled?(:maintenance_mode) }
  before_action :configure_permitted_parameters, if: :devise_controller?

  before_action :staging_authenticate
  before_action :set_active_storage_host
  before_action :setup_javascript_settings
  before_action :setup_tracking
  before_action :set_locale

  helper_method :multiple_devise_profile_connect?, :instructeur_signed_in?, :current_instructeur, :current_expert, :expert_signed_in?,
    :administrateur_signed_in?, :current_administrateur, :current_account

  def staging_authenticate
    if StagingAuthService.enabled? && !authenticate_with_http_basic { |username, password| StagingAuthService.authenticate(username, password) }
      request_http_basic_authentication
    end
  end

  def multiple_devise_profile_connect?
    user_signed_in? && instructeur_signed_in? ||
        instructeur_signed_in? && administrateur_signed_in? ||
        instructeur_signed_in? && expert_signed_in? ||
        user_signed_in? && administrateur_signed_in? ||
        user_signed_in? && expert_signed_in?
  end

  def current_instructeur
    current_user&.instructeur
  end

  def instructeur_signed_in?
    user_signed_in? && current_user&.instructeur.present?
  end

  def current_administrateur
    current_user&.administrateur
  end

  def administrateur_signed_in?
    current_administrateur.present?
  end

  def current_expert
    current_user&.expert
  end

  def expert_signed_in?
    current_expert.present?
  end

  def current_account
    {
      administrateur: current_administrateur,
      instructeur: current_instructeur,
      user: current_user
    }.compact
  end

  alias_method :pundit_user, :current_account

  protected

  def feature_enabled?(feature_name)
    Flipper.enabled?(feature_name, current_user)
  end

  def authenticate_logged_user!
    if instructeur_signed_in?
      authenticate_instructeur!
    elsif expert_signed_in?
      authenticate_expert!
    elsif administrateur_signed_in?
      authenticate_administrateur!
    else
      authenticate_user!
    end
  end

  def authenticate_instructeur!
    if !instructeur_signed_in?
      redirect_to new_user_session_path
    end
  end

  def authenticate_expert!
    if !expert_signed_in?
      redirect_to new_user_session_path
    end
  end

  def authenticate_administrateur!
    if !administrateur_signed_in?
      redirect_to new_user_session_path
    end
  end

  def after_sign_out_path_for(_resource_or_scope)
    stored_location_for(:user) || super
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [:otp_attempt])
  end

  private

  def set_current_roles
    Current.administrateur = current_administrateur
    Current.instructeur = current_instructeur
  end

  def set_active_storage_host
    ActiveStorage::Current.host = request.base_url
  end

  def setup_javascript_settings
    gon.autosave = Rails.application.config.ds_autosave
    gon.autocomplete = Rails.application.secrets.autocomplete
  end

  def setup_tracking
    gon.matomo = matomo_config
    gon.sentry = sentry_config

    if administrateur_signed_in?
      gon.sendinblue = sendinblue_config
      gon.crisp = crisp_config
    end
  end

  def current_user_roles
    @current_user_roles ||= begin
      roles = [
        current_user,
        current_instructeur,
        current_administrateur,
        current_super_admin
      ].compact.map { |role| role.class.name }

      roles.any? ? roles.join(', ') : 'Guest'
    end
  end

  def set_sentry_user
    Sentry.set_user(sentry_user)
  end

  # private method called by rails fwk
  # see https://github.com/roidrage/lograge
  def append_info_to_payload(payload)
    super

    payload.merge!({
      user_agent: request.user_agent,
      user_id: current_user&.id,
      user_email: current_user&.email,
      user_roles: current_user_roles
    }.compact)

    if browser.known?
      payload.merge!({
        browser: browser.name,
        browser_version: browser.version.to_s,
        platform: browser.platform.name
      })
    end

    payload
  end

  def reject
    authorized_request =
      request.path_info == '/' ||
      request.path_info.start_with?('/manager') ||
      request.path_info.start_with?('/super_admins')

    api_request = request.path_info.start_with?('/api/')

    if super_admin_signed_in? || authorized_request
      flash.now.alert = MAINTENANCE_MESSAGE
    elsif api_request
      render json: { error: MAINTENANCE_MESSAGE }.to_json, status: :service_unavailable
    else
      [:user, :instructeur, :administrateur].each { |role| sign_out(role) }
      flash[:alert] = MAINTENANCE_MESSAGE
      redirect_to root_path
    end
  end

  def redirect_if_untrusted
    if instructeur_signed_in? &&
        sensitive_path &&
        !feature_enabled?(:instructeur_bypass_email_login_token) &&
        !IPService.ip_trusted?(request.headers['X-Forwarded-For']) &&
        !trusted_device?

      # return at this location
      # after the device is trusted
      if get_stored_location_for(:user).blank?
        store_location_for(:user, request.fullpath)
      end

      send_login_token_or_bufferize(current_instructeur)
      redirect_to link_sent_path(email: current_instructeur.email)
    end
  end

  def sensitive_path
    path = request.path_info

    if path == '/' ||
      path == '/users/sign_out' ||
      path == '/contact' ||
      path == '/contact-admin' ||
      path.start_with?('/connexion-par-jeton') ||
      path.start_with?('/api/') ||
      path.start_with?('/lien-envoye')

      false
    else
      true
    end
  end

  def sentry_user
    { id: user_signed_in? ? "User##{current_user.id}" : 'Guest' }
  end

  def sentry_config
    sentry = Rails.application.secrets.sentry

    {
      key: sentry[:client_key],
      enabled: sentry[:enabled],
      environment: sentry[:environment],
      browser: { modern: BrowserSupport.supported?(browser) },
      user: sentry_user
    }
  end

  def matomo_config
    matomo = Rails.application.secrets.matomo

    {
      key: matomo[:client_key],
      enabled: matomo[:enabled]
    }
  end

  def sendinblue_config
    sendinblue = Rails.application.secrets.sendinblue

    {
      key: sendinblue[:client_key],
      enabled: sendinblue[:enabled],
      administrateur: {
        email: current_user&.email,
        payload: {
          DS_SIGN_IN_COUNT: current_user&.sign_in_count,
          DS_CREATED_AT: current_administrateur&.created_at,
          DS_ACTIVE: current_user&.active?,
          DS_ID: current_administrateur&.id,
          DS_GESTIONNAIRE_ID: current_instructeur&.id,
          DS_ROLES: current_user_roles
        }
      }
    }
  end

  def crisp_config
    crisp = Rails.application.secrets.crisp

    nb_demarches_by_state = if current_administrateur.present?
      current_administrateur.procedures.group(:aasm_state).count
    else
      {}
    end

    {
      key: crisp[:client_key],
      enabled: crisp[:enabled],
      administrateur: {
        email: current_user&.email,
        DS_SIGN_IN_COUNT: current_user&.sign_in_count,
        DS_CREATED_AT: current_administrateur&.created_at,
        DS_ID: current_administrateur&.id,
        DS_NB_DEMARCHES_BROUILLONS: nb_demarches_by_state['brouillon'],
        DS_NB_DEMARCHES_ACTIVES: nb_demarches_by_state['publiee'],
        DS_NB_DEMARCHES_ARCHIVES: nb_demarches_by_state['close']
      }
    }
  end

  def current_email
    current_user&.email
  end

  def set_locale
    if feature_enabled?(:localization)
      I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
    end
  end
end
