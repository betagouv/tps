feature 'Inviting an expert:' do
  include ActiveJob::TestHelper
  include ActionView::Helpers

  let(:instructeur) { create(:instructeur, password: 'my-s3cure-p4ssword') }
  let(:expert) { create(:expert, password: expert_password) }
  let(:expert_password) { 'mot de passe d’expert' }
  let(:procedure) { create(:procedure, :published, instructeurs: [instructeur]) }
  let(:dossier) { create(:dossier, :en_construction, :with_dossier_link, procedure: procedure) }
  let(:linked_dossier) { Dossier.find_by(id: dossier.reload.champs.filter(&:dossier_link?).map(&:value).compact) }

  context 'as an Instructeur' do
    scenario 'I can invite an expert' do
      # assign instructeur to linked dossier
      instructeur.assign_to_procedure(linked_dossier.procedure)

      login_as instructeur.user, scope: :user
      visit instructeur_dossier_path(procedure, dossier)

      click_on 'Avis externes'
      expect(page).to have_current_path(avis_instructeur_dossier_path(procedure, dossier))

      fill_in 'avis_emails', with: 'expert1@expert.com, expert2@expert.com'
      fill_in 'avis_introduction', with: 'Bonjour, merci de me donner votre avis sur ce dossier.'
      check 'avis_invite_linked_dossiers'
      page.select 'confidentiel', from: 'avis_confidentiel'

      click_on 'Demander un avis'
      perform_enqueued_jobs

      expect(page).to have_content('Une demande d\'avis a été envoyée')
      expect(page).to have_content('Avis des invités')
      within('.list-avis') do
        expect(page).to have_content('expert1@expert.com')
        expect(page).to have_content('expert2@expert.com')
        expect(page).to have_content('Bonjour, merci de me donner votre avis sur ce dossier.')
      end

      expect(Avis.count).to eq(4)
      expect(emails_sent_to('expert1@expert.com').size).to eq(1)
      expect(emails_sent_to('expert2@expert.com').size).to eq(1)

      invitation_email = open_email('expert1@expert.com')
      avis = Avis.find_by(expert: expert.id)
      sign_up_link = sign_up_expert_avis_path(avis.dossier.procedure, avis, avis.expert.email)
      expect(invitation_email.body).to include(sign_up_link)
    end

    context 'when experts submitted their answer' do
      let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: procedure) }
      let!(:answered_avis) { create(:avis, :with_answer, dossier: dossier, claimant: instructeur, experts_procedure: experts_procedure) }

      scenario 'I can read the expert answer' do
        login_as instructeur.user, scope: :user
        visit instructeur_dossier_path(procedure, dossier)

        click_on 'Avis externes'

        expect(page).to have_content(answered_avis.expert.email)
        answered_avis.answer.split("\n").each do |answer_line|
          expect(page).to have_content(answer_line)
        end
      end
    end
  end
end
