class ActiveStorage::DownloadableFile
  def self.create_list_from_dossier(dossier)
    pjs = PiecesJustificativesService.liste_pieces_justificatives(dossier)
    files = pjs.map do |piece_justificative|
      [
        piece_justificative,
        self.timestamped_filename(piece_justificative)
      ]
    end
    files << [dossier.pdf_export_for_instructeur, self.timestamped_filename(dossier.pdf_export_for_instructeur)]
    files
  end

  private

  def self.timestamped_filename(attachment)
    # we pad the original file name with a timestamp
    # and a short id in order to help identify multiple versions and avoid name collisions
    folder = self.folder(attachment)
    extension = File.extname(attachment.filename.to_s)
    basename = File.basename(attachment.filename.to_s, extension)
    timestamp = attachment.created_at.strftime("%d-%m-%Y-%H-%M")
    id = attachment.id % 10000

    "#{folder}/#{basename}-#{timestamp}-#{id}#{extension}"
  end

  def self.folder(attachment)
    case attachment.record_type
    when 'Dossier'
      'dossier'
    when 'DossierOperationLog', 'BillSignature'
      'horodatage'
    when 'Commentaire'
      'messagerie'
    else
      'pieces_justificatives'
    end
  end

  def using_local_backend?
    [:local, :local_test, :test].include?(Rails.application.config.active_storage.service)
  end
end
