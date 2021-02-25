# == Schema Information
#
# Table name: avis
#
#  id                   :integer          not null, primary key
#  answer               :text
#  claimant_type        :string
#  confidentiel         :boolean          default(FALSE), not null
#  email                :string
#  introduction         :text
#  revoked_at           :datetime
#  tmp_expert_migrated  :boolean          default(FALSE)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  claimant_id          :integer          not null
#  dossier_id           :integer
#  experts_procedure_id :bigint
#  instructeur_id       :integer
#
class Avis < ApplicationRecord
  include EmailSanitizableConcern

  belongs_to :dossier, inverse_of: :avis, touch: true, optional: false
  belongs_to :instructeur, optional: true
  belongs_to :experts_procedure, optional: true
  belongs_to :claimant, class_name: 'Instructeur', optional: false

  has_one_attached :piece_justificative_file
  has_one_attached :introduction_file
  has_one :expert, through: :experts_procedure
  has_one :procedure, through: :experts_procedure

  validates :piece_justificative_file,
    content_type: AUTHORIZED_CONTENT_TYPES,
    size: { less_than: 20.megabytes }

  validates :introduction_file,
    content_type: AUTHORIZED_CONTENT_TYPES,
    size: { less_than: 20.megabytes }

  validates :email, format: { with: Devise.email_regexp, message: "n'est pas valide" }, allow_nil: true
  validates :claimant, presence: true
  validates :piece_justificative_file, size: { less_than: 20.megabytes }
  validates :introduction_file, size: { less_than: 20.megabytes }

  before_validation -> { sanitize_email(:email) }

  default_scope { joins(:dossier) }
  scope :with_answer, -> { where.not(answer: nil) }
  scope :without_answer, -> { where(answer: nil) }
  scope :for_dossier, -> (dossier_id) { where(dossier_id: dossier_id) }
  scope :by_latest, -> { order(updated_at: :desc) }
  scope :updated_since?, -> (date) { where('avis.updated_at > ?', date) }

  # The form allows subtmitting avis requests to several emails at once,
  # hence this virtual attribute.
  attr_accessor :emails
  attr_accessor :invite_linked_dossiers

  def claimant
    claimant_id = read_attribute(:claimant_id)
    claimant_type = read_attribute(:claimant_type)
    if claimant_type == 'Instructeur' || !tmp_expert_migrated
      Instructeur.find(claimant_id)
    else
      Expert.find(claimant_id).user.expert
    end
  end

  def claimant=(claimant)
    self.claimant_id = claimant.id

    if claimant.is_a? Instructeur
      self.claimant_type = 'Instructeur'
    else
      self.claimant_type = 'Expert'
      self.tmp_expert_migrated = true
    end
  end

  def email_to_display
    instructeur&.email || email
  end

  def self.link_avis_to_instructeur(instructeur)
    Avis.where(email: instructeur.email).update_all(email: nil, instructeur_id: instructeur.id)
  end

  def self.avis_exists_and_email_belongs_to_avis?(avis_id, email)
    Avis.find_by(id: avis_id)&.email == email
  end

  def spreadsheet_columns
    [
      ['Dossier ID', dossier_id.to_s],
      ['Question / Introduction', :introduction],
      ['Réponse', :answer],
      ['Créé le', :created_at],
      ['Répondu le', :updated_at],
      ['Instructeur', claimant&.email],
      ['Expert', expert&.email]
    ]
  end

  def revoked?
    revoked_at.present?
  end

  def revivable_by?(reviver)
    revokable_by?(reviver)
  end

  def revokable_by?(revocator)
    revocator.dossiers.include?(dossier) || revocator == claimant
  end

  def revoke_by!(revocator)
    return false if !revokable_by?(revocator)

    if answer.present?
      update!(revoked_at: Time.zone.now)
    else
      destroy!
    end
  end
end
