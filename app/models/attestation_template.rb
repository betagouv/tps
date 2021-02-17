# == Schema Information
#
# Table name: attestation_templates
#
#  id           :integer          not null, primary key
#  activated    :boolean
#  body         :text
#  footer       :text
#  title        :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  procedure_id :integer
#
class AttestationTemplate < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  include TagsSubstitutionConcern

  belongs_to :procedure, optional: false

  has_one_attached :logo
  has_one_attached :signature

  validates :footer, length: { maximum: 190 }
  validates :logo, content_type: ['image/png', 'image/jpg', 'image/jpeg'], size: { less_than: 1.megabytes }
  validates :signature, content_type: ['image/png', 'image/jpg', 'image/jpeg'], size: { less_than: 1.megabytes }

  DOSSIER_STATE = Dossier.states.fetch(:accepte)

  def attestation_for(dossier)
    attestation = Attestation.new(title: replace_tags(title, dossier))
    attestation.pdf.attach(
      io: build_pdf(dossier),
      filename: "attestation-dossier-#{dossier.id}.pdf",
      content_type: 'application/pdf',
      # we don't want to run virus scanner on this file
      metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
    )
    attestation
  end

  def unspecified_champs_for_dossier(dossier)
    all_champs_with_libelle_index = (dossier.champs + dossier.champs_private)
      .reduce({}) do |acc, champ|
        acc[champ.libelle] = champ
        acc
      end

    used_tags.map do |used_tag|
      corresponding_champ = all_champs_with_libelle_index[used_tag]

      if corresponding_champ && corresponding_champ.value.blank?
        corresponding_champ
      end
    end.compact
  end

  def dup
    attestation_template = AttestationTemplate.new(title: title, body: body, footer: footer, activated: activated)

    if logo.attached?
      attestation_template.logo.attach(
        io: StringIO.new(logo.download),
        filename: logo.filename.to_s,
        content_type: logo.content_type,
        # we don't want to run virus scanner on duplicated file
        metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
      )
    end

    if signature.attached?
      attestation_template.signature.attach(
        io: StringIO.new(signature.download),
        filename: signature.filename.to_s,
        content_type: signature.content_type,
        # we don't want to run virus scanner on duplicated file
        metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
      )
    end

    attestation_template
  end

  def logo_url
    if logo.attached?
      Rails.application.routes.url_helpers.url_for(logo)
    end
  end

  def signature_url
    if signature.attached?
      Rails.application.routes.url_helpers.url_for(signature)
    end
  end

  def render_attributes_for(params = {})
    dossier = params.fetch(:dossier, false)

    {
      created_at: Time.zone.now,
      title: dossier ? replace_tags(title, dossier) : params.fetch(:title, title),
      body: dossier ? replace_tags(body, dossier) : params.fetch(:body, body),
      footer: params.fetch(:footer, footer),
      logo: params.fetch(:logo, logo.attached? ? logo : nil),
      signature: params.fetch(:signature, signature.attached? ? signature : nil)
    }
  end

  private

  def used_tags
    delimiters_regex = /--(?<capture>((?!--).)*)--/

    # We can't use flat_map as scan will return 3 levels of array,
    # using flat_map would give us 2, whereas flatten will
    # give us 1, which is what we want
    [title, body]
      .map { |str| str.scan(delimiters_regex) }
      .flatten
  end

  def build_pdf(dossier)
    attestation = render_attributes_for(dossier: dossier)
    attestation_view = ApplicationController.render(
      template: 'new_administrateur/attestation_templates/show',
      formats: :pdf,
      assigns: { attestation: attestation }
    )

    StringIO.new(attestation_view)
  end
end
