namespace :after_party do
  desc 'Deployment task: backfill_claimant_id_for_experts_on_avis_table'
  task backfill_claimant_id_for_experts_on_avis_table: :environment do
    puts "Running deploy task 'backfill_claimant_id_for_experts_on_avis_table'"

    avis_experts_claimant = Avis.where(claimant_type: 'Expert', tmp_expert_migrated: false)
    progress = ProgressReport.new(avis_experts_claimant.count)

    avis_experts_claimant.find_each do |avis|
      claimant_instructeur = Instructeur.find(avis.claimant_id)
      if claimant_instructeur.user
        claimant_expert = claimant_instructeur.user.expert
        if !claimant_expert
          User.create_or_promote_to_expert(claimant_instructeur.user.email, SecureRandom.hex)
          claimant_expert = claimant_instructeur.reload.user.expert
          ExpertsProcedure.find_or_create_by(procedure: avis.procedure, expert: claimant_expert)
        end
        avis.update_columns(claimant_id: claimant_expert.id, tmp_expert_migrated: true)
      else
        # Avis associated to an Instructeur with no user are bad data: delete it
        avis.destroy!
      end
      progress.inc
    end
    progress.finish
    # Update task as completed.  If you remove the line below, the task will
    # run with every deploy (or every time you call after_party:run).
    AfterParty::TaskRecord
      .create version: AfterParty::TaskRecorder.new(__FILE__).timestamp
  end
end
