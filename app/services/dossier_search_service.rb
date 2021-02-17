class DossierSearchService
  def self.matching_dossiers_for_instructeur(search_terms, instructeur)
    dossier_by_exact_id_for_instructeur(search_terms, instructeur)
      .presence || dossier_by_full_text_for_instructeur(search_terms, instructeur)
  end

  def self.matching_dossiers_for_user(search_terms, user)
    dossier_by_exact_id_for_user(search_terms, user)
      .presence || dossier_by_full_text_for_user(search_terms, user.dossiers) || dossier_by_full_text_for_user(search_terms, user.dossiers_invites)
  end

  private

  def self.dossier_by_exact_id_for_instructeur(search_terms, instructeur)
    id = search_terms.to_i
    if id != 0 && id_compatible?(id) # Sometimes instructeur is searching dossiers with a big number (ex: SIRET), ActiveRecord can't deal with them and throws ActiveModel::RangeError. id_compatible? prevents this.
      dossiers_by_id(id, instructeur)
    else
      Dossier.none
    end
  end

  def self.dossiers_by_id(id, instructeur)
    (instructeur.dossiers.where(id: id) + instructeur.dossiers_from_avis.where(id: id)).uniq
  end

  def self.id_compatible?(number)
    ActiveRecord::Type::Integer.new.serialize(number)
    true
  rescue ActiveModel::RangeError
    false
  end

  def self.dossier_by_full_text_for_user(search_terms, dossiers)
    ts_vector = "to_tsvector('french', search_terms)"
    ts_query = "to_tsquery('french', #{Dossier.connection.quote(to_tsquery(search_terms))})"

    dossiers
      .where("#{ts_vector} @@ #{ts_query}")
      .order(Arel.sql("COALESCE(ts_rank(#{ts_vector}, #{ts_query}), 0) DESC"))
  end

  def self.dossier_by_exact_id_for_user(search_terms, user)
    id = search_terms.to_i
    if id != 0 && id_compatible?(id) # Sometimes user is searching dossiers with a big number (ex: SIRET), ActiveRecord can't deal with them and throws ActiveModel::RangeError. id_compatible? prevents this.
      Dossier.where(id: user.dossiers.where(id: id) + user.dossiers_invites.where(id: id)).distinct
    else
      Dossier.none
    end
  end

  def self.dossier_by_full_text_for_instructeur(search_terms, instructeur)
    ts_vector = "to_tsvector('french', search_terms || private_search_terms)"
    ts_query = "to_tsquery('french', #{Dossier.connection.quote(to_tsquery(search_terms))})"

    instructeur
      .dossiers
      .state_not_brouillon
      .where("#{ts_vector} @@ #{ts_query}")
      .order(Arel.sql("COALESCE(ts_rank(#{ts_vector}, #{ts_query}), 0) DESC"))
  end

  def self.to_tsquery(search_terms)
    (search_terms || "")
      .gsub(/['?\\:&|!<>()]/, "") # drop disallowed characters
      .strip
      .split(/\s+/)           # split words
      .map { |x| "#{x}:*" }   # enable prefix matching
      .join(" & ")
  end
end
