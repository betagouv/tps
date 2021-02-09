# == Schema Information
#
# Table name: experts
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Expert < ApplicationRecord
  has_one :user
  has_many :experts_procedures
  has_many :avis, through: :experts_procedures
  has_many :dossiers, through: :avis

  default_scope { eager_load(:user) }

  def email
    user.email
  end

  def self.by_email(email)
    Expert.eager_load(:user).find_by(users: { email: email })
  end
end
