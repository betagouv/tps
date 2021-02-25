class AvisSerializer < ActiveModel::Serializer
  attributes :answer,
    :introduction,
    :created_at,
    :answered_at

  def email
    object.expert.email
  end

  def created_at
    object.created_at&.in_time_zone('UTC')
  end

  def answered_at
    object.updated_at&.in_time_zone('UTC')
  end
end
