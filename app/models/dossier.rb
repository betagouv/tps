# == Schema Information
#
# Table name: dossiers
#
#  id                                                 :integer          not null, primary key
#  api_entreprise_job_exceptions                      :string           is an Array
#  archived                                           :boolean          default(FALSE)
#  autorisation_donnees                               :boolean
#  brouillon_close_to_expiration_notice_sent_at       :datetime
#  en_construction_at                                 :datetime
#  en_construction_close_to_expiration_notice_sent_at :datetime
#  en_construction_conservation_extension             :interval         default(0 seconds)
#  en_instruction_at                                  :datetime
#  groupe_instructeur_updated_at                      :datetime
#  hidden_at                                          :datetime
#  last_avis_updated_at                               :datetime
#  last_champ_private_updated_at                      :datetime
#  last_champ_updated_at                              :datetime
#  last_commentaire_updated_at                        :datetime
#  motivation                                         :text
#  private_search_terms                               :text
#  processed_at                                       :datetime
#  search_terms                                       :text
#  state                                              :string
#  termine_close_to_expiration_notice_sent_at         :datetime
#  created_at                                         :datetime
#  updated_at                                         :datetime
#  groupe_instructeur_id                              :bigint
#  revision_id                                        :bigint
#  user_id                                            :integer
#
class Dossier < ApplicationRecord
  include DossierFilteringConcern

  include Discard::Model
  self.discard_column = :hidden_at
  default_scope -> { kept }

  enum state: {
    brouillon:       'brouillon',
    en_construction: 'en_construction',
    en_instruction:  'en_instruction',
    accepte:         'accepte',
    refuse:          'refuse',
    sans_suite:      'sans_suite'
  }

  EN_CONSTRUCTION_OU_INSTRUCTION = [states.fetch(:en_construction), states.fetch(:en_instruction)]
  TERMINE = [states.fetch(:accepte), states.fetch(:refuse), states.fetch(:sans_suite)]
  INSTRUCTION_COMMENCEE = TERMINE + [states.fetch(:en_instruction)]
  SOUMIS = EN_CONSTRUCTION_OU_INSTRUCTION + TERMINE

  TAILLE_MAX_ZIP = 100.megabytes

  REMAINING_DAYS_BEFORE_CLOSING = 2
  INTERVAL_BEFORE_CLOSING = "#{REMAINING_DAYS_BEFORE_CLOSING} days"
  INTERVAL_BEFORE_EXPIRATION = '1 month'
  INTERVAL_EXPIRATION = '1 month 5 days'

  has_one :etablissement, dependent: :destroy
  has_one :individual, validate: false, dependent: :destroy
  has_one :attestation, dependent: :destroy
  has_one :france_connect_information, through: :user

  has_one_attached :justificatif_motivation
  has_one_attached :pdf_export_for_instructeur

  has_many :champs, -> { root.public_ordered }, inverse_of: :dossier, dependent: :destroy
  has_many :champs_private, -> { root.private_ordered }, class_name: 'Champ', inverse_of: :dossier, dependent: :destroy
  has_many :commentaires, inverse_of: :dossier, dependent: :destroy
  has_many :invites, dependent: :destroy
  has_many :follows, -> { active }, inverse_of: :dossier
  has_many :previous_follows, -> { inactive }, class_name: 'Follow', inverse_of: :dossier
  has_many :followers_instructeurs, through: :follows, source: :instructeur
  has_many :previous_followers_instructeurs, -> { distinct }, through: :previous_follows, source: :instructeur
  has_many :avis, inverse_of: :dossier, dependent: :destroy
  has_many :experts, through: :avis
  has_many :traitements, -> { order(:processed_at) }, inverse_of: :dossier, dependent: :destroy

  has_many :dossier_operation_logs, -> { order(:created_at) }, inverse_of: :dossier

  belongs_to :groupe_instructeur, optional: true
  belongs_to :revision, class_name: 'ProcedureRevision', optional: false
  belongs_to :user, optional: false

  has_one :procedure, through: :revision
  has_many :types_de_champ, through: :revision
  has_many :types_de_champ_private, through: :revision

  accepts_nested_attributes_for :champs
  accepts_nested_attributes_for :champs_private

  include AASM

  aasm whiny_persistence: true, column: :state, enum: true do
    state :brouillon, initial: true
    state :en_construction
    state :en_instruction
    state :accepte
    state :refuse
    state :sans_suite

    event :passer_en_construction, after: :after_passer_en_construction do
      transitions from: :brouillon, to: :en_construction
    end

    event :passer_en_instruction, after: :after_passer_en_instruction do
      transitions from: :en_construction, to: :en_instruction
    end

    event :passer_automatiquement_en_instruction, after: :after_passer_automatiquement_en_instruction do
      transitions from: :en_construction, to: :en_instruction
    end

    event :repasser_en_construction, after: :after_repasser_en_construction do
      transitions from: :en_instruction, to: :en_construction
    end

    event :accepter, after: :after_accepter do
      transitions from: :en_instruction, to: :accepte
    end

    event :accepter_automatiquement, after: :after_accepter_automatiquement do
      transitions from: :en_construction, to: :accepte
    end

    event :refuser, after: :after_refuser do
      transitions from: :en_instruction, to: :refuse
    end

    event :classer_sans_suite, after: :after_classer_sans_suite do
      transitions from: :en_instruction, to: :sans_suite
    end

    event :repasser_en_instruction, after: :after_repasser_en_instruction do
      transitions from: :refuse, to: :en_instruction
      transitions from: :sans_suite, to: :en_instruction
      transitions from: :accepte, to: :en_instruction
    end
  end

  scope :state_brouillon,                      -> { where(state: states.fetch(:brouillon)) }
  scope :state_not_brouillon,                  -> { where.not(state: states.fetch(:brouillon)) }
  scope :state_en_construction,                -> { where(state: states.fetch(:en_construction)) }
  scope :state_en_instruction,                 -> { where(state: states.fetch(:en_instruction)) }
  scope :state_en_construction_ou_instruction, -> { where(state: EN_CONSTRUCTION_OU_INSTRUCTION) }
  scope :state_instruction_commencee,          -> { where(state: INSTRUCTION_COMMENCEE) }
  scope :state_termine,                        -> { where(state: TERMINE) }

  scope :archived,      -> { where(archived: true) }
  scope :not_archived,  -> { where(archived: false) }

  scope :order_by_updated_at, -> (order = :desc) { order(updated_at: order) }
  scope :order_by_created_at, -> (order = :asc) { order(en_construction_at: order, created_at: order, id: order) }
  scope :updated_since,       -> (since) { where('dossiers.updated_at >= ?', since) }
  scope :created_since,       -> (since) { where('dossiers.en_construction_at >= ?', since) }

  scope :with_type_de_champ, -> (stable_id) {
    joins('INNER JOIN champs ON champs.dossier_id = dossiers.id INNER JOIN types_de_champ ON types_de_champ.id = champs.type_de_champ_id')
      .where('types_de_champ.private = FALSE AND types_de_champ.stable_id = ?', stable_id)
  }

  scope :with_type_de_champ_private, -> (stable_id) {
    joins('INNER JOIN champs ON champs.dossier_id = dossiers.id INNER JOIN types_de_champ ON types_de_champ.id = champs.type_de_champ_id')
      .where('types_de_champ.private = TRUE AND types_de_champ.stable_id = ?', stable_id)
  }

  scope :all_state,                   -> { not_archived.state_not_brouillon }
  scope :en_construction,             -> { not_archived.state_en_construction }
  scope :en_instruction,              -> { not_archived.state_en_instruction }
  scope :termine,                     -> { not_archived.state_termine }
  scope :downloadable_sorted,         -> {
    state_not_brouillon
      .includes(
        :user,
        :individual,
        :followers_instructeurs,
        :avis,
        :traitements,
        etablissement: :champ,
        champs: {
          type_de_champ: [],
          etablissement: :champ,
          piece_justificative_file_attachment: :blob,
          champs: [
            type_de_champ: [],
            piece_justificative_file_attachment: :blob
          ]
        },
        champs_private: {
          type_de_champ: [],
          etablissement: :champ,
          piece_justificative_file_attachment: :blob,
          champs: [
            type_de_champ: [],
            piece_justificative_file_attachment: :blob
          ]
        },
        procedure: :groupe_instructeurs
      ).order(en_construction_at: 'asc')
  }
  scope :en_cours,                    -> { not_archived.state_en_construction_ou_instruction }
  scope :without_followers,           -> { left_outer_joins(:follows).where(follows: { id: nil }) }
  scope :with_champs,                 -> { includes(champs: :type_de_champ) }
  scope :for_api, -> {
    includes(commentaires: { piece_jointe_attachment: :blob },
      champs: [
        :geo_areas,
        :etablissement,
        piece_justificative_file_attachment: :blob,
        champs: [
          piece_justificative_file_attachment: :blob
        ]
      ],
      champs_private: [
        :geo_areas,
        :etablissement,
        piece_justificative_file_attachment: :blob,
        champs: [
          piece_justificative_file_attachment: :blob
        ]
      ],
      justificatif_motivation_attachment: :blob,
      attestation: [],
      avis: { piece_justificative_file_attachment: :blob },
      traitements: [],
      etablissement: [],
      individual: [],
      user: [])
  }

  scope :with_notifiable_procedure, -> (opts = { notify_on_closed: false }) do
    states = opts[:notify_on_closed] ? [:publiee, :close, :depubliee] : [:publiee, :depubliee]
    joins(:procedure)
      .where(procedures: { aasm_state: states })
  end

  scope :brouillon_close_to_expiration, -> do
    state_brouillon
      .joins(:procedure)
      .where("dossiers.created_at + (duree_conservation_dossiers_dans_ds * INTERVAL '1 month') - INTERVAL :expires_in < :now", { now: Time.zone.now, expires_in: INTERVAL_BEFORE_EXPIRATION })
  end
  scope :en_construction_close_to_expiration, -> do
    state_en_construction
      .joins(:procedure)
      .where("dossiers.en_construction_at + dossiers.en_construction_conservation_extension + (duree_conservation_dossiers_dans_ds * INTERVAL '1 month') - INTERVAL :expires_in < :now", { now: Time.zone.now, expires_in: INTERVAL_BEFORE_EXPIRATION })
  end
  scope :en_instruction_close_to_expiration, -> do
    state_en_instruction
      .joins(:procedure)
      .where("dossiers.en_instruction_at + (duree_conservation_dossiers_dans_ds * INTERVAL '1 month') - INTERVAL :expires_in < :now", { now: Time.zone.now, expires_in: INTERVAL_BEFORE_EXPIRATION })
  end
  def self.termine_close_to_expiration
    dossier_ids = Traitement.termine_close_to_expiration.pluck(:dossier_id).uniq
    Dossier.where(id: dossier_ids)
  end

  scope :brouillon_expired, -> do
    state_brouillon
      .where("brouillon_close_to_expiration_notice_sent_at + INTERVAL :expires_in < :now", { now: Time.zone.now, expires_in: INTERVAL_EXPIRATION })
  end
  scope :en_construction_expired, -> do
    state_en_construction
      .where("en_construction_close_to_expiration_notice_sent_at + INTERVAL :expires_in < :now", { now: Time.zone.now, expires_in: INTERVAL_EXPIRATION })
  end
  scope :termine_expired, -> do
    state_termine
      .where("termine_close_to_expiration_notice_sent_at + INTERVAL :expires_in < :now", { now: Time.zone.now, expires_in: INTERVAL_EXPIRATION })
  end

  scope :without_brouillon_expiration_notice_sent, -> { where(brouillon_close_to_expiration_notice_sent_at: nil) }
  scope :without_en_construction_expiration_notice_sent, -> { where(en_construction_close_to_expiration_notice_sent_at: nil) }
  scope :without_termine_expiration_notice_sent, -> { where(termine_close_to_expiration_notice_sent_at: nil) }

  scope :discarded_brouillon_expired, -> do
    with_discarded
      .discarded
      .state_brouillon
      .where('hidden_at < ?', 1.week.ago)
  end
  scope :discarded_en_construction_expired, -> do
    with_discarded
      .discarded
      .state_en_construction
      .where('dossiers.hidden_at < ?', 1.week.ago)
  end
  scope :discarded_termine_expired, -> do
    with_discarded
      .discarded
      .state_termine
      .where('dossiers.hidden_at < ?', 1.week.ago)
  end

  scope :brouillon_near_procedure_closing_date, -> do
    # select users who have submitted dossier for the given 'procedures.id'
    users_who_submitted =
      state_not_brouillon
        .joins(:revision)
        .where("procedure_revisions.procedure_id = procedures.id")
        .select(:user_id)
    # select dossier in brouillon where procedure closes in two days and for which the user has not submitted a Dossier
    state_brouillon
      .with_notifiable_procedure
      .where("procedures.auto_archive_on - INTERVAL :before_closing = :now", { now: Time.zone.today, before_closing: INTERVAL_BEFORE_CLOSING })
      .where.not(user: users_who_submitted)
  end

  scope :for_procedure, -> (procedure) { includes(:user, :groupe_instructeur).where(groupe_instructeurs: { procedure: procedure }) }
  scope :for_api_v2, -> { includes(procedure: [:administrateurs, :attestation_template], etablissement: [], individual: [], traitements: []) }

  scope :with_notifications, -> do
    joins(:follows)
      .where('last_champ_updated_at > follows.demande_seen_at' \
      ' OR groupe_instructeur_updated_at > follows.demande_seen_at' \
      ' OR last_champ_private_updated_at > follows.annotations_privees_seen_at' \
      ' OR last_avis_updated_at > follows.avis_seen_at' \
      ' OR last_commentaire_updated_at > follows.messagerie_seen_at')
      .distinct
  end

  accepts_nested_attributes_for :individual

  delegate :siret, :siren, to: :etablissement, allow_nil: true
  delegate :france_connect_information, to: :user

  before_save :build_default_champs, if: Proc.new { revision_id_was.nil? }
  before_save :update_search_terms

  after_save :send_dossier_received
  after_save :send_web_hook
  after_create_commit :send_draft_notification_email

  validates :user, presence: true
  validates :individual, presence: true, if: -> { revision.procedure.for_individual? }
  validates :groupe_instructeur, presence: true, if: -> { !brouillon? }

  def motivation
    return nil if !termine?
    traitements.any? ? traitements.last.motivation : read_attribute(:motivation)
  end

  def processed_at
    return nil if !termine?
    traitements.any? ? traitements.last.processed_at : read_attribute(:processed_at)
  end

  def update_search_terms
    self.search_terms = [
      user&.email,
      *champs.flat_map(&:search_terms),
      *etablissement&.search_terms,
      individual&.nom,
      individual&.prenom
    ].compact.join(' ')
    self.private_search_terms = champs_private.flat_map(&:search_terms).compact.join(' ')
  end

  def build_default_champs
    revision.build_champs.each do |champ|
      champs << champ
    end
    revision.build_champs_private.each do |champ|
      champs_private << champ
    end
  end

  def build_default_individual
    if procedure.for_individual? && individual.blank?
      self.individual = if france_connect_information.present?
        Individual.from_france_connect(france_connect_information)
      else
        Individual.new
      end
    end
  end

  def en_construction_ou_instruction?
    EN_CONSTRUCTION_OU_INSTRUCTION.include?(state)
  end

  def termine?
    TERMINE.include?(state)
  end

  def instruction_commencee?
    INSTRUCTION_COMMENCEE.include?(state)
  end

  def reset!
    etablissement.destroy

    update_columns(autorisation_donnees: false)
  end

  def read_only?
    en_instruction? || accepte? || refuse? || sans_suite?
  end

  def can_transition_to_en_construction?
    brouillon? && procedure.dossier_can_transition_to_en_construction?
  end

  def can_be_updated_by_user?
    brouillon? || en_construction?
  end

  def can_be_deleted_by_user?
    brouillon? || en_construction?
  end

  def can_be_deleted_by_manager?
    kept? && can_be_deleted_by_user?
  end

  def messagerie_available?
    !brouillon? && !archived
  end

  def en_construction_close_to_expiration?
    Dossier.en_construction_close_to_expiration.where(id: self).present?
  end

  def show_groupe_instructeur_details?
    procedure.routee? && groupe_instructeur.present? && (!procedure.feature_enabled?(:procedure_routage_api) || !defaut_groupe_instructeur?)
  end

  def show_groupe_instructeur_selector?
    procedure.routee? && !procedure.feature_enabled?(:procedure_routage_api)
  end

  def assign_to_groupe_instructeur(groupe_instructeur, author = nil)
    if (groupe_instructeur.nil? || groupe_instructeur.procedure == procedure) && self.groupe_instructeur != groupe_instructeur
      if update(groupe_instructeur: groupe_instructeur, groupe_instructeur_updated_at: Time.zone.now)
        unfollow_stale_instructeurs

        if author.present?
          log_dossier_operation(author, :changer_groupe_instructeur, self)
        end

        true
      end
    else
      false
    end
  end

  def archiver!(author)
    update!(archived: true)
    log_dossier_operation(author, :archiver)
  end

  def desarchiver!(author)
    update!(archived: false)
    log_dossier_operation(author, :desarchiver)
  end

  def text_summary
    if brouillon?
      parts = [
        "Dossier en brouillon répondant à la démarche ",
        procedure.libelle,
        " gérée par l'organisme ",
        procedure.organisation_name
      ]
    else
      parts = [
        "Dossier déposé le ",
        en_construction_at.strftime("%d/%m/%Y"),
        " sur la démarche ",
        procedure.libelle,
        " gérée par l'organisme ",
        procedure.organisation_name
      ]
    end

    parts.join
  end

  def avis_for_instructeur(instructeur)
    if instructeur.dossiers.include?(self)
      avis.order(created_at: :asc)
    else
      avis
        .where(confidentiel: false)
        .or(avis.where(claimant_id: instructeur.id, claimant_type: 'Instructeur'))
        .or(avis.where(instructeur: instructeur))
        .order(created_at: :asc)
    end
  end

  def avis_for_expert(expert)
    if expert.dossiers.include?(self)
      avis.order(created_at: :asc)
    else
      instructeur = expert.user.instructeur.id if expert.user.instructeur
      avis
        .where(confidentiel: false)
        .or(avis.where(claimant_id: expert.id, claimant_type: 'Expert', tmp_expert_migrated: true))
        .or(avis.where(claimant_id: instructeur, claimant_type: 'Instructeur', tmp_expert_migrated: false))
        .or(avis.where(expert: expert))
        .order(created_at: :asc)
    end
  end

  def owner_name
    if etablissement.present?
      etablissement.entreprise_raison_sociale
    elsif individual.present?
      "#{individual.nom} #{individual.prenom}"
    end
  end

  def log_operations?
    !procedure.brouillon?
  end

  def keep_track_on_deletion?
    !procedure.brouillon?
  end

  def expose_legacy_carto_api?
    procedure.expose_legacy_carto_api?
  end

  def geo_position
    if etablissement.present?
      point = Geocoder.search(etablissement.geo_adresse).first
    end

    lon = Champs::CarteChamp::DEFAULT_LON.to_s
    lat = Champs::CarteChamp::DEFAULT_LAT.to_s
    zoom = "13"

    if point.present?
      lat, lon = point.coordinates.map(&:to_s)
    end

    { lon: lon, lat: lat, zoom: zoom }
  end

  def unspecified_attestation_champs
    attestation_template = procedure.attestation_template

    if attestation_template&.activated?
      attestation_template.unspecified_champs_for_dossier(self)
    else
      []
    end
  end

  def build_attestation
    if procedure.attestation_template&.activated?
      procedure.attestation_template.attestation_for(self)
    end
  end

  def expired_keep_track!
    if keep_track_on_deletion?
      DeletedDossier.create_from_dossier(self, :expired)
      log_automatic_dossier_operation(:supprimer, self)
    end
  end

  def discard_and_keep_track!(author, reason)
    if keep_track_on_deletion?
      if en_construction?
        deleted_dossier = DeletedDossier.create_from_dossier(self, reason)

        administration_emails = followers_instructeurs.present? ? followers_instructeurs.map(&:email) : procedure.administrateurs.map(&:email)
        administration_emails.each do |email|
          DossierMailer.notify_deletion_to_administration(deleted_dossier, email).deliver_later
        end
        DossierMailer.notify_deletion_to_user(deleted_dossier, user.email).deliver_later

        log_dossier_operation(author, :supprimer, self)
      elsif termine?
        deleted_dossier = DeletedDossier.create_from_dossier(self, reason)

        DossierMailer.notify_instructeur_deletion_to_user(deleted_dossier, user.email).deliver_later

        log_dossier_operation(author, :supprimer, self)
      end
    end

    discard!
  end

  def restore(author, only_discarded_with_procedure = false)
    if discarded?
      deleted_dossier = DeletedDossier.find_by(dossier_id: id)

      if !only_discarded_with_procedure || deleted_dossier&.procedure_removed?
        if undiscard && keep_track_on_deletion? && en_construction?
          deleted_dossier&.destroy
          log_dossier_operation(author, :restaurer, self)
        end
      end
    end
  end

  def after_passer_en_construction
    update!(en_construction_at: Time.zone.now) if self.en_construction_at.nil?
  end

  def after_passer_en_instruction(instructeur)
    instructeur.follow(self)

    update!(en_instruction_at: Time.zone.now) if self.en_instruction_at.nil?
    log_dossier_operation(instructeur, :passer_en_instruction)
  end

  def after_passer_automatiquement_en_instruction
    update!(en_instruction_at: Time.zone.now) if self.en_instruction_at.nil?
    log_automatic_dossier_operation(:passer_en_instruction)
  end

  def after_repasser_en_construction(instructeur)
    log_dossier_operation(instructeur, :repasser_en_construction)
  end

  def after_repasser_en_instruction(instructeur)
    self.archived = false
    self.en_instruction_at = Time.zone.now
    attestation&.destroy

    save!
    DossierMailer.notify_revert_to_instruction(self).deliver_later
    log_dossier_operation(instructeur, :repasser_en_instruction)
  end

  def after_accepter(instructeur, motivation, justificatif = nil)
    self.traitements.build(state: Dossier.states.fetch(:accepte), instructeur_email: instructeur.email, motivation: motivation, processed_at: Time.zone.now)

    if justificatif
      self.justificatif_motivation.attach(justificatif)
    end

    if attestation.nil?
      self.attestation = build_attestation
    end

    save!
    remove_titres_identite!
    NotificationMailer.send_closed_notification(self).deliver_later
    log_dossier_operation(instructeur, :accepter, self)
  end

  def after_accepter_automatiquement
    self.traitements.build(state: Dossier.states.fetch(:accepte), instructeur_email: nil, motivation: nil, processed_at: Time.zone.now)
    self.en_instruction_at ||= Time.zone.now

    if attestation.nil?
      self.attestation = build_attestation
    end

    save!
    remove_titres_identite!
    NotificationMailer.send_closed_notification(self).deliver_later
    log_automatic_dossier_operation(:accepter, self)
  end

  def after_refuser(instructeur, motivation, justificatif = nil)
    self.traitements.build(state: Dossier.states.fetch(:refuse), instructeur_email: instructeur.email, motivation: motivation, processed_at: Time.zone.now)

    if justificatif
      self.justificatif_motivation.attach(justificatif)
    end

    save!
    remove_titres_identite!
    NotificationMailer.send_refused_notification(self).deliver_later
    log_dossier_operation(instructeur, :refuser, self)
  end

  def after_classer_sans_suite(instructeur, motivation, justificatif = nil)
    self.traitements.build(state: Dossier.states.fetch(:sans_suite), instructeur_email: instructeur.email, motivation: motivation, processed_at: Time.zone.now)

    if justificatif
      self.justificatif_motivation.attach(justificatif)
    end

    save!
    remove_titres_identite!
    NotificationMailer.send_without_continuation_notification(self).deliver_later
    log_dossier_operation(instructeur, :classer_sans_suite, self)
  end

  def remove_titres_identite!
    champs.filter(&:titre_identite?).map(&:piece_justificative_file).each(&:purge_later)
  end

  def check_mandatory_champs
    (champs + champs.filter(&:repetition?).flat_map(&:champs))
      .filter(&:mandatory_and_blank?)
      .map do |champ|
        "Le champ #{champ.libelle.truncate(200)} doit être rempli."
      end
  end

  def log_modifier_annotations!(instructeur)
    champs_private.filter(&:value_previously_changed?).each do |champ|
      log_dossier_operation(instructeur, :modifier_annotation, champ)
    end
  end

  def log_modifier_annotation!(champ, instructeur)
    log_dossier_operation(instructeur, :modifier_annotation, champ)
  end

  def demander_un_avis!(avis)
    log_dossier_operation(avis.claimant, :demander_un_avis, avis)
  end

  def spreadsheet_columns_csv(types_de_champ:, types_de_champ_private:)
    spreadsheet_columns(with_etablissement: true, types_de_champ: types_de_champ, types_de_champ_private: types_de_champ_private)
  end

  def spreadsheet_columns_xlsx(types_de_champ:, types_de_champ_private:)
    spreadsheet_columns(types_de_champ: types_de_champ, types_de_champ_private: types_de_champ_private)
  end

  def spreadsheet_columns_ods(types_de_champ:, types_de_champ_private:)
    spreadsheet_columns(types_de_champ: types_de_champ, types_de_champ_private: types_de_champ_private)
  end

  def spreadsheet_columns(with_etablissement: false, types_de_champ:, types_de_champ_private:)
    columns = [
      ['ID', id.to_s],
      ['Email', user.email]
    ]

    if procedure.for_individual?
      columns += [
        ['Civilité', individual&.gender],
        ['Nom', individual&.nom],
        ['Prénom', individual&.prenom]
      ]
      if procedure.ask_birthday
        columns += [['Date de naissance', individual&.birthdate]]
      end
    elsif with_etablissement
      columns += [
        ['Établissement SIRET', etablissement&.siret],
        ['Établissement siège social', etablissement&.siege_social],
        ['Établissement NAF', etablissement&.naf],
        ['Établissement libellé NAF', etablissement&.libelle_naf],
        ['Établissement Adresse', etablissement&.adresse],
        ['Établissement numero voie', etablissement&.numero_voie],
        ['Établissement type voie', etablissement&.type_voie],
        ['Établissement nom voie', etablissement&.nom_voie],
        ['Établissement complément adresse', etablissement&.complement_adresse],
        ['Établissement code postal', etablissement&.code_postal],
        ['Établissement localité', etablissement&.localite],
        ['Établissement code INSEE localité', etablissement&.code_insee_localite],
        ['Entreprise SIREN', etablissement&.entreprise_siren],
        ['Entreprise capital social', etablissement&.entreprise_capital_social],
        ['Entreprise numero TVA intracommunautaire', etablissement&.entreprise_numero_tva_intracommunautaire],
        ['Entreprise forme juridique', etablissement&.entreprise_forme_juridique],
        ['Entreprise forme juridique code', etablissement&.entreprise_forme_juridique_code],
        ['Entreprise nom commercial', etablissement&.entreprise_nom_commercial],
        ['Entreprise raison sociale', etablissement&.entreprise_raison_sociale],
        ['Entreprise SIRET siège social', etablissement&.entreprise_siret_siege_social],
        ['Entreprise code effectif entreprise', etablissement&.entreprise_code_effectif_entreprise],
        ['Entreprise date de création', etablissement&.entreprise_date_creation],
        ['Entreprise nom', etablissement&.entreprise_nom],
        ['Entreprise prénom', etablissement&.entreprise_prenom],
        ['Association RNA', etablissement&.association_rna],
        ['Association titre', etablissement&.association_titre],
        ['Association objet', etablissement&.association_objet],
        ['Association date de création', etablissement&.association_date_creation],
        ['Association date de déclaration', etablissement&.association_date_declaration],
        ['Association date de publication', etablissement&.association_date_publication]
      ]
    else
      columns << ['Entreprise raison sociale', etablissement&.entreprise_raison_sociale]
    end

    columns += [
      ['Archivé', :archived],
      ['État du dossier', I18n.t(state, scope: [:activerecord, :attributes, :dossier, :state])],
      ['Dernière mise à jour le', :updated_at],
      ['Déposé le', :en_construction_at],
      ['Passé en instruction le', :en_instruction_at],
      ['Traité le', :processed_at],
      ['Motivation de la décision', :motivation],
      ['Instructeurs', followers_instructeurs.map(&:email).join(' ')]
    ]

    if procedure.routee?
      columns << ['Groupe instructeur', groupe_instructeur.label]
    end

    columns + champs_for_export(types_de_champ) + champs_private_for_export(types_de_champ_private)
  end

  def champs_for_export(types_de_champ)
    # Index values by stable_id
    values = champs.reject(&:exclude_from_export?).reduce({}) do |champs, champ|
      champs[champ.stable_id] = champ.for_export
      champs
    end

    # Get all the champs values for the types de champ in the final list.
    # Dossier might not have corresponding champ – display nil.
    types_de_champ.map do |type_de_champ|
      [type_de_champ.libelle, values[type_de_champ.stable_id]]
    end
  end

  def champs_private_for_export(types_de_champ)
    # Index values by stable_id
    values = champs_private.reject(&:exclude_from_export?).reduce({}) do |champs, champ|
      champs[champ.stable_id] = champ.for_export
      champs
    end

    # Get all the champs values for the types de champ in the final list.
    # Dossier might not have corresponding champ – display nil.
    types_de_champ.map do |type_de_champ|
      [type_de_champ.libelle, values[type_de_champ.stable_id]]
    end
  end

  def attachments_downloadable?
    PiecesJustificativesService.liste_pieces_justificatives(self).present? \
      && PiecesJustificativesService.pieces_justificatives_total_size(self) < Dossier::TAILLE_MAX_ZIP
  end

  def linked_dossiers_for(instructeur_or_expert)
    dossier_ids = champs.filter(&:dossier_link?).map(&:value).compact
    instructeur_or_expert.dossiers.where(id: dossier_ids)
  end

  def hash_for_deletion_mail
    { id: self.id, procedure_libelle: self.procedure.libelle }
  end

  def geo_data?
    geo_areas.present?
  end

  def to_feature_collection
    {
      type: 'FeatureCollection',
      id: id,
      bbox: bounding_box,
      features: geo_areas.map(&:to_feature)
    }
  end

  def log_api_entreprise_job_exception(exception)
    exceptions = self.api_entreprise_job_exceptions ||= []
    exceptions << exception.inspect
    update_column(:api_entreprise_job_exceptions, exceptions)
  end

  private

  def defaut_groupe_instructeur?
    groupe_instructeur == procedure.defaut_groupe_instructeur
  end

  def geo_areas
    champs.includes(:geo_areas).flat_map(&:geo_areas) + champs_private.includes(:geo_areas).flat_map(&:geo_areas)
  end

  def bounding_box
    factory = RGeo::Geographic.simple_mercator_factory
    bounding_box = RGeo::Cartesian::BoundingBox.new(factory)

    geo_areas.map(&:rgeo_geometry).compact.each do |geometry|
      bounding_box.add(geometry)
    end

    [bounding_box.max_point, bounding_box.min_point].compact.flat_map(&:coordinates)
  end

  def log_dossier_operation(author, operation, subject = nil)
    if log_operations?
      DossierOperationLog.create_and_serialize(
        dossier: self,
        operation: DossierOperationLog.operations.fetch(operation),
        author: author,
        subject: subject
      )
    end
  end

  def log_automatic_dossier_operation(operation, subject = nil)
    if log_operations?
      DossierOperationLog.create_and_serialize(
        dossier: self,
        operation: DossierOperationLog.operations.fetch(operation),
        automatic_operation: true,
        subject: subject
      )
    end
  end

  def send_dossier_received
    if saved_change_to_state? && en_instruction? && !procedure.declarative_accepte?
      NotificationMailer.send_dossier_received(self).deliver_later
    end
  end

  def send_draft_notification_email
    if brouillon? && !procedure.declarative?
      DossierMailer.notify_new_draft(self).deliver_later
    end
  end

  def send_web_hook
    if saved_change_to_state? && !brouillon? && procedure.web_hook_url.present?
      WebHookJob.perform_later(
        procedure,
        self
      )
    end
  end

  def unfollow_stale_instructeurs
    followers_instructeurs.each do |instructeur|
      if instructeur.groupe_instructeurs.exclude?(groupe_instructeur)
        instructeur.unfollow(self)
        if kept?
          DossierMailer.notify_groupe_instructeur_changed(instructeur, self).deliver_later
        end
      end
    end
  end

  def self.notify_draft_not_submitted
    brouillon_near_procedure_closing_date
      .includes(:user)
      .find_each do |dossier|
        DossierMailer.notify_brouillon_not_submitted(dossier).deliver_later
      end
  end
end
