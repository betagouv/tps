namespace :after_party do
  desc 'Deployment task: backfill_claimant_type_on_avis_table'
  task backfill_claimant_type_on_avis_table: :environment do
    puts "Running deploy task 'backfill_claimant_type_on_avis_table'"

    with_dossiers = Avis.where(claimant_type: nil).includes(claimant: :assign_to).where.not(claimant: { assign_tos: { id: nil } })
    with_dossiers.update_all(claimant_type: 'Instructeur')

    without_dossiers = Avis.where(claimant_type: nil).includes(claimant: :assign_to).where(claimant: { assign_tos: { id: nil } })
    without_dossiers.find_each do |avis|
      claimant = avis.claimant.user
      instructeur = avis.instructeur

      if instructeur && avis.experts_procedure_id.blank?
        User.create_or_promote_to_expert(instructeur.user.email, SecureRandom.hex)
        instructeur.user.reload
        experts_procedure = ExpertsProcedure.find_or_create_by(procedure: avis.procedure, expert: instructeur.user.expert)
        avis.update_columns(claimant_type: 'Expert', experts_procedure_id: experts_procedure.id)

      elsif instructeur.blank? && avis.experts_procedure_id.blank?
        expert = User.create_or_promote_to_expert(avis.email, SecureRandom.hex).expert
        expert.reload
        experts_procedure = ExpertsProcedure.find_or_create_by(procedure: avis.procedure, expert: expert)
        avis.update_columns(claimant_type: 'Expert', experts_procedure_id: experts_procedure.id)

      elsif avis.experts_procedure_id.present?
        avis.update_column(:claimant_type, 'Expert')

      elsif claimant.blank?
        avis.destroy
      end
    end

    # Update task as completed.  If you remove the line below, the task will
    # run with every deploy (or every time you call after_party:run).
    AfterParty::TaskRecord
      .create version: AfterParty::TaskRecorder.new(__FILE__).timestamp
  end
end
