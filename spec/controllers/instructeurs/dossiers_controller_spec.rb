describe Instructeurs::DossiersController, type: :controller do
  render_views

  let(:instructeur) { create(:instructeur) }
  let(:administrateur) { create(:administrateur) }
  let(:administration) { create(:administration) }
  let(:instructeurs) { [instructeur] }
  let(:procedure) { create(:procedure, :published, :for_individual, instructeurs: instructeurs) }
  let(:dossier) { create(:dossier, :en_construction, :with_individual, procedure: procedure) }
  let(:fake_justificatif) { fixture_file_upload('spec/fixtures/files/piece_justificative_0.pdf', 'application/pdf') }

  before { sign_in(instructeur.user) }

  describe '#attestation' do
    context 'when a dossier has an attestation' do
      let(:dossier) { create(:dossier, :accepte, attestation: create(:attestation, :with_pdf), procedure: procedure) }

      it 'redirects to a service tmp_url' do
        get :attestation, params: { procedure_id: procedure.id, dossier_id: dossier.id }
        expect(response.location).to match '/rails/active_storage/disk/'
      end
    end
  end

  describe '#send_to_instructeurs' do
    let(:recipient) { create(:instructeur) }
    let(:instructeurs) { [instructeur, recipient] }
    let(:mail) { double("mail") }

    before do
      expect(mail).to receive(:deliver_later)

      expect(InstructeurMailer)
        .to receive(:send_dossier)
        .with(instructeur, dossier, recipient)
        .and_return(mail)

      post(
        :send_to_instructeurs,
        params: {
          recipients: [recipient.id].to_json,
          procedure_id: procedure.id,
          dossier_id: dossier.id
        }
      )
    end

    it { expect(response).to redirect_to(personnes_impliquees_instructeur_dossier_url) }
    it { expect(recipient.followed_dossiers).to include(dossier) }
  end

  describe '#follow' do
    before do
      patch :follow, params: { procedure_id: procedure.id, dossier_id: dossier.id }
    end

    it { expect(instructeur.followed_dossiers).to match([dossier]) }
    it { expect(flash.notice).to eq('Dossier suivi') }
    it { expect(response).to redirect_to(instructeur_procedures_url) }
  end

  describe '#unfollow' do
    before do
      instructeur.followed_dossiers << dossier
      patch :unfollow, params: { procedure_id: procedure.id, dossier_id: dossier.id }
      instructeur.reload
    end

    it { expect(instructeur.followed_dossiers).to match([]) }
    it { expect(flash.notice).to eq("Vous ne suivez plus le dossier nº #{dossier.id}") }
    it { expect(response).to redirect_to(instructeur_procedures_url) }
  end

  describe '#archive' do
    before do
      instructeur.follow(dossier)
      patch :archive, params: { procedure_id: procedure.id, dossier_id: dossier.id }
      dossier.reload
      instructeur.reload
    end

    it { expect(dossier.archived).to be true }
    it { expect(response).to redirect_to(instructeur_procedures_url) }
  end

  describe '#unarchive' do
    before do
      dossier.update(archived: true)
      patch :unarchive, params: { procedure_id: procedure.id, dossier_id: dossier.id }
      dossier.reload
    end

    it { expect(dossier.archived).to be false }
    it { expect(response).to redirect_to(instructeur_procedures_url) }
  end

  describe '#passer_en_instruction' do
    let(:dossier) { create(:dossier, :en_construction, procedure: procedure) }

    before do
      sign_in(instructeur.user)
      post :passer_en_instruction, params: { procedure_id: procedure.id, dossier_id: dossier.id }, format: 'js'
    end

    it { expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_instruction)) }
    it { expect(instructeur.follow?(dossier)).to be true }
    it { expect(response).to have_http_status(:ok) }
    it { expect(response.body).to include('.header-actions') }

    context 'when the dossier has already been put en_instruction' do
      let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }

      it 'warns about the error' do
        expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_instruction))
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_text('Le dossier est déjà en instruction.')
      end
    end

    context 'when the dossier has already been closed' do
      let(:dossier) { create(:dossier, :accepte, procedure: procedure) }

      it 'doesn’t change the dossier state' do
        expect(dossier.reload.state).to eq(Dossier.states.fetch(:accepte))
      end

      it 'warns about the error' do
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_text('Le dossier est en ce moment accepté : il n’est pas possible de le passer en instruction.')
      end
    end
  end

  describe '#repasser_en_construction' do
    let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }

    before do
      sign_in(instructeur.user)
      post :repasser_en_construction,
        params: { procedure_id: procedure.id, dossier_id: dossier.id },
        format: 'js'
    end

    it { expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_construction)) }
    it { expect(response).to have_http_status(:ok) }
    it { expect(response.body).to include('.header-actions') }

    context 'when the dossier has already been put en_construction' do
      let(:dossier) { create(:dossier, :en_construction, procedure: procedure) }

      it 'warns about the error' do
        expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_construction))
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_text('Le dossier est déjà en construction.')
      end
    end
  end

  describe '#repasser_en_instruction' do
    let(:dossier) { create(:dossier, :refuse, procedure: procedure) }
    let(:current_user) { instructeur.user }

    before do
      sign_in current_user
      post :repasser_en_instruction,
        params: { procedure_id: procedure.id, dossier_id: dossier.id },
        format: 'js'
    end

    it { expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_instruction)) }
    it { expect(response).to have_http_status(:ok) }
    it { expect(response.body).to include('.header-actions') }

    context 'when the dossier has already been put en_instruction' do
      let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }

      it 'warns about the error' do
        expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_instruction))
        expect(response).to have_http_status(:ok)
        expect(response.body).to have_text('Le dossier est déjà en instruction.')
      end
    end

    context 'when the dossier is accepte' do
      let(:dossier) { create(:dossier, :accepte, procedure: procedure) }

      it 'it is possible to go back to en_instruction as instructeur' do
        expect(dossier.reload.state).to eq(Dossier.states.fetch(:en_instruction))
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe '#terminer' do
    context "with refuser" do
      before do
        dossier.passer_en_instruction!(instructeur)
        sign_in(instructeur.user)
      end

      context 'simple refusal' do
        subject { post :terminer, params: { process_action: "refuser", procedure_id: procedure.id, dossier_id: dossier.id }, format: 'js' }

        it 'change state to refuse' do
          subject

          dossier.reload
          expect(dossier.state).to eq(Dossier.states.fetch(:refuse))
          expect(dossier.justificatif_motivation).to_not be_attached
        end

        it 'Notification email is sent' do
          expect(NotificationMailer).to receive(:send_refused_notification)
            .with(dossier).and_return(NotificationMailer)
          expect(NotificationMailer).to receive(:deliver_later)

          subject
        end
      end

      context 'refusal with a justificatif' do
        subject { post :terminer, params: { process_action: "refuser", procedure_id: procedure.id, dossier_id: dossier.id, dossier: { justificatif_motivation: fake_justificatif } }, format: 'js' }

        it 'attachs a justificatif' do
          subject

          dossier.reload
          expect(dossier.state).to eq(Dossier.states.fetch(:refuse))
          expect(dossier.justificatif_motivation).to be_attached
        end

        it { expect(subject.body).to include('.header-actions') }
      end
    end

    context "with classer_sans_suite" do
      before do
        dossier.passer_en_instruction!(instructeur)
        sign_in(instructeur.user)
      end
      context 'without attachment' do
        subject { post :terminer, params: { process_action: "classer_sans_suite", procedure_id: procedure.id, dossier_id: dossier.id }, format: 'js' }

        it 'change state to sans_suite' do
          subject

          dossier.reload
          expect(dossier.state).to eq(Dossier.states.fetch(:sans_suite))
          expect(dossier.justificatif_motivation).to_not be_attached
        end

        it 'Notification email is sent' do
          expect(NotificationMailer).to receive(:send_without_continuation_notification)
            .with(dossier).and_return(NotificationMailer)
          expect(NotificationMailer).to receive(:deliver_later)

          subject
        end

        it { expect(subject.body).to include('.header-actions') }
      end

      context 'with attachment' do
        subject { post :terminer, params: { process_action: "classer_sans_suite", procedure_id: procedure.id, dossier_id: dossier.id, dossier: { justificatif_motivation: fake_justificatif } }, format: 'js' }

        it 'change state to sans_suite' do
          subject

          dossier.reload
          expect(dossier.state).to eq(Dossier.states.fetch(:sans_suite))
          expect(dossier.justificatif_motivation).to be_attached
        end

        it { expect(subject.body).to include('.header-actions') }
      end
    end

    context "with accepter" do
      before do
        dossier.passer_en_instruction!(instructeur)
        sign_in(instructeur.user)

        expect(NotificationMailer).to receive(:send_closed_notification)
          .with(dossier)
          .and_return(NotificationMailer)

        expect(NotificationMailer).to receive(:deliver_later)
      end

      subject { post :terminer, params: { process_action: "accepter", procedure_id: procedure.id, dossier_id: dossier.id }, format: 'js' }

      it 'change state to accepte' do
        subject

        dossier.reload
        expect(dossier.state).to eq(Dossier.states.fetch(:accepte))
        expect(dossier.justificatif_motivation).to_not be_attached
      end

      context 'when the dossier does not have any attestation' do
        it 'Notification email is sent' do
          subject
        end
      end

      context 'when the dossier has an attestation' do
        before do
          attestation = Attestation.new
          allow(attestation).to receive(:pdf).and_return(double(read: 'pdf', size: 2.megabytes, attached?: false))
          allow(attestation).to receive(:pdf_url).and_return('http://some_document_url')

          allow_any_instance_of(Dossier).to receive(:build_attestation).and_return(attestation)
        end

        it 'The instructeur is sent back to the dossier page' do
          expect(subject.body).to include('.header-actions')
        end

        context 'and the dossier has already an attestation' do
          it 'should not crash' do
            dossier.attestation = Attestation.new
            dossier.save
            expect(subject.body).to include('.header-actions')
          end
        end
      end

      context 'when the attestation template uses the motivation field' do
        let(:emailable) { false }
        let(:template) { create(:attestation_template) }
        let(:procedure) { create(:procedure, :published, :for_individual, attestation_template: template, instructeurs: [instructeur]) }

        subject do
          post :terminer, params: {
            process_action: "accepter",
            procedure_id: procedure.id,
            dossier_id: dossier.id,
            dossier: { motivation: "Yallah" }
          }, format: 'js'
        end

        before do
          Timecop.freeze(Time.zone.now)

          expect_any_instance_of(AttestationTemplate)
            .to receive(:attestation_for)
            .with(have_attributes(motivation: "Yallah", processed_at: Time.zone.now))
        end

        after { Timecop.return }

        it { subject }
      end

      context 'with an attachment' do
        subject { post :terminer, params: { process_action: "accepter", procedure_id: procedure.id, dossier_id: dossier.id, dossier: { justificatif_motivation: fake_justificatif } }, format: 'js' }

        it 'change state to accepte' do
          subject

          dossier.reload
          expect(dossier.state).to eq(Dossier.states.fetch(:accepte))
          expect(dossier.justificatif_motivation).to be_attached
        end

        it { expect(subject.body).to include('.header-actions') }
      end
    end

    context 'when a dossier is already closed' do
      let(:dossier) { create(:dossier, :accepte, procedure: procedure) }

      before { allow(dossier).to receive(:after_accepter) }

      subject { post :terminer, params: { process_action: "accepter", procedure_id: procedure.id, dossier_id: dossier.id, dossier: { justificatif_motivation: fake_justificatif } }, format: 'js' }

      it 'does not close it again' do
        subject

        expect(dossier).not_to have_received(:after_accepter)
        expect(dossier.state).to eq(Dossier.states.fetch(:accepte))

        expect(response).to have_http_status(:ok)
        expect(response.body).to have_text('Le dossier est déjà accepté.')
      end
    end
  end

  describe "#create_commentaire" do
    let(:saved_commentaire) { dossier.commentaires.first }
    let(:body) { "avant\napres" }
    let(:file) { fixture_file_upload('spec/fixtures/files/piece_justificative_0.pdf', 'application/pdf') }
    let(:scan_result) { true }
    let(:now) { Timecop.freeze("09/11/1989") }

    subject {
      post :create_commentaire, params: {
        procedure_id: procedure.id,
        dossier_id: dossier.id,
        commentaire: {
          body: body,
          file: file
        }
      }
    }

    before do
      allow(ClamavService).to receive(:safe_file?).and_return(scan_result)
      Timecop.freeze(now)
    end

    after { Timecop.return }

    it "creates a commentaire" do
      expect { subject }.to change(Commentaire, :count).by(1)
      expect(instructeur.followed_dossiers).to include(dossier)

      expect(response).to redirect_to(messagerie_instructeur_dossier_path(dossier.procedure, dossier))
      expect(flash.notice).to be_present
      expect(dossier.reload.last_commentaire_updated_at).to eq(now)
    end

    context "when the commentaire created with virus file" do
      let(:scan_result) { false }

      it "creates a commentaire (shows message that file have a virus)" do
        expect { subject }.to change(Commentaire, :count).by(1)
        expect(instructeur.followed_dossiers).to include(dossier)

        expect(response).to redirect_to(messagerie_instructeur_dossier_path(dossier.procedure, dossier))
        expect(flash.notice).to be_present
      end
    end
  end

  describe "#create_avis" do
    let(:expert) { create(:expert) }
    let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: dossier.procedure) }
    let(:invite_linked_dossiers) { false }
    let(:saved_avis) { dossier.avis.first }
    let!(:old_avis_count) { Avis.count }

    subject do
      post :create_avis, params: {
        procedure_id: procedure.id,
        dossier_id: dossier.id,
        avis: { emails: emails, introduction: 'intro', confidentiel: true, invite_linked_dossiers: invite_linked_dossiers, claimant: instructeur, experts_procedure: experts_procedure }
      }
    end

    let(:emails) { ['email@a.com'] }

    context "notifications updates" do
      context 'when an instructeur follows the dossier' do
        let(:follower) { create(:instructeur) }
        before { follower.follow(dossier) }

        it 'the follower has a notification' do
          expect(follower.followed_dossiers.with_notifications).to eq([])
          subject
          expect(follower.followed_dossiers.with_notifications).to eq([dossier.reload])
        end
      end
    end

    context 'email sending' do
      before do
        subject
      end

      it { expect(saved_avis.expert.email).to eq('email@a.com') }
      it { expect(saved_avis.introduction).to eq('intro') }
      it { expect(saved_avis.confidentiel).to eq(true) }
      it { expect(saved_avis.dossier).to eq(dossier) }
      it { expect(saved_avis.claimant).to eq(instructeur) }
      it { expect(response).to redirect_to(avis_instructeur_dossier_path(dossier.procedure, dossier)) }

      context "with an invalid email" do
        let(:emails) { ['emaila.com'] }

        before { subject }

        it { expect(response).to render_template :avis }
        it { expect(flash.alert).to eq(["emaila.com : Email n'est pas valide"]) }
        it { expect { subject }.not_to change(Avis, :count) }
        it { expect(dossier.last_avis_updated_at).to eq(nil) }
      end

      context 'with multiple emails' do
        let(:emails) { ["toto.fr,titi@titimail.com"] }

        before { subject }

        it { expect(response).to render_template :avis }
        it { expect(flash.alert).to eq(["toto.fr : Email n'est pas valide"]) }
        it { expect(flash.notice).to eq("Une demande d'avis a été envoyée à titi@titimail.com") }
        it { expect(Avis.count).to eq(old_avis_count + 1) }
        it { expect(saved_avis.expert.email).to eq("titi@titimail.com") }
      end

      context 'with linked dossiers' do
        let(:asked_confidentiel) { false }
        let(:previous_avis_confidentiel) { false }
        let(:dossier) { create(:dossier, :en_construction, :with_dossier_link, procedure: procedure) }
        before { subject }
        context 'when the expert doesn’t share linked dossiers' do
          let(:invite_linked_dossiers) { false }

          it 'sends a single avis for the main dossier, but doesn’t give access to the linked dossiers' do
            expect(flash.notice).to eq("Une demande d'avis a été envoyée à email@a.com")
            expect(Avis.count).to eq(old_avis_count + 1)
            expect(saved_avis.expert.email).to eq("email@a.com")
            expect(saved_avis.dossier).to eq(dossier)
          end
        end

        context 'when the expert also shares the linked dossiers' do
          let(:invite_linked_dossiers) { true }

          context 'and the expert can access the linked dossiers' do
            let(:saved_avis) { Avis.last(2).first }
            let(:linked_avis) { Avis.last }
            let(:linked_dossier) { Dossier.find_by(id: dossier.reload.champs.filter(&:dossier_link?).map(&:value).compact) }
            let(:invite_linked_dossiers) do
              instructeur.assign_to_procedure(linked_dossier.procedure)
              true
            end

            it 'sends one avis for the main dossier' do
              expect(flash.notice).to eq("Une demande d'avis a été envoyée à email@a.com")
              expect(saved_avis.expert.email).to eq("email@a.com")
              expect(saved_avis.dossier).to eq(dossier)
            end

            it 'sends another avis for the linked dossiers' do
              expect(Avis.count).to eq(old_avis_count + 2)
              expect(linked_avis.dossier).to eq(linked_dossier)
            end
          end

          context 'but the expert can’t access the linked dossier' do
            it 'sends a single avis for the main dossier, but doesn’t give access to the linked dossiers' do
              expect(flash.notice).to eq("Une demande d'avis a été envoyée à email@a.com")
              expect(Avis.count).to eq(old_avis_count + 1)
              expect(saved_avis.expert.email).to eq("email@a.com")
              expect(saved_avis.dossier).to eq(dossier)
            end
          end
        end
      end
    end
  end

  describe "#show" do
    context "when the dossier is exported as PDF" do
      let(:instructeur) { create(:instructeur) }
      let(:expert) { create(:expert) }
      let(:procedure) { create(:procedure, :published, instructeurs: instructeurs) }
      let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: procedure) }
      let(:dossier) do
        create(:dossier,
          :accepte,
          :with_all_champs,
          :with_all_annotations,
          :with_motivation,
          :with_entreprise,
          :with_commentaires, procedure: procedure)
      end
      let!(:avis) { create(:avis, dossier: dossier, claimant: instructeur, experts_procedure: experts_procedure) }

      subject do
        avis
        get :show, params: {
          procedure_id: procedure.id,
          dossier_id: dossier.id,
          format: :pdf
        }
      end

      before { subject }

      it { expect(assigns(:include_infos_administration)).to eq(true) }
      it { expect(response).to render_template 'dossiers/show' }
    end
  end

  describe "#update_annotations" do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_private: [
        build(:type_de_champ_multiple_drop_down_list, position: 0),
        build(:type_de_champ_linked_drop_down_list, position: 1),
        build(:type_de_champ_datetime, position: 2),
        build(:type_de_champ_repetition, :with_types_de_champ, position: 3)
      ], instructeurs: instructeurs)
    end
    let(:dossier) { create(:dossier, :en_construction, :with_all_annotations, procedure: procedure) }
    let(:another_instructeur) { create(:instructeur) }
    let(:now) { Time.zone.parse('01/01/2100') }

    let(:champ_multiple_drop_down_list) do
      dossier.champs_private.first
    end

    let(:champ_linked_drop_down_list) do
      dossier.champs_private.second
    end

    let(:champ_datetime) do
      dossier.champs_private.third
    end

    let(:champ_repetition) do
      dossier.champs_private.fourth
    end

    before do
      another_instructeur.follow(dossier)
      Timecop.freeze(now)
      patch :update_annotations, params: params

      champ_multiple_drop_down_list.reload
      champ_linked_drop_down_list.reload
      champ_datetime.reload
      champ_repetition.reload
    end

    after do
      Timecop.return
    end

    context "with new values for champs_private" do
      let(:params) do
        {
          procedure_id: procedure.id,
          dossier_id: dossier.id,
          dossier: {
            champs_private_attributes: {
              '0': {
                id: champ_multiple_drop_down_list.id,
                value: ['', 'un', 'deux']
              },
              '1': {
                id: champ_datetime.id,
                'value(1i)': 2019,
                'value(2i)': 12,
                'value(3i)': 21,
                'value(4i)': 13,
                'value(5i)': 17
              },
              '2': {
                id: champ_linked_drop_down_list.id,
                primary_value: 'primary',
                secondary_value: 'secondary'
              },
              '3': {
                id: champ_repetition.id,
                champs_attributes: {
                  id: champ_repetition.champs.first.id,
                  value: 'text'
                }
              }
            }
          }
        }
      end

      it {
        expect(champ_multiple_drop_down_list.value).to eq('["un", "deux"]')
        expect(champ_linked_drop_down_list.primary_value).to eq('primary')
        expect(champ_linked_drop_down_list.secondary_value).to eq('secondary')
        expect(champ_datetime.value).to eq('21/12/2019 13:17')
        expect(champ_repetition.champs.first.value).to eq('text')
        expect(dossier.reload.last_champ_private_updated_at).to eq(now)
        expect(response).to redirect_to(annotations_privees_instructeur_dossier_path(dossier.procedure, dossier))
      }

      it 'updates the annotations' do
        Timecop.travel(now + 1.hour)
        expect(instructeur.followed_dossiers.with_notifications).to eq([])
        expect(another_instructeur.followed_dossiers.with_notifications).to eq([dossier.reload])
      end
    end

    context "without new values for champs_private" do
      let(:params) do
        {
          procedure_id: procedure.id,
          dossier_id: dossier.id,
          dossier: {
            champs_private_attributes: {},
            champs_attributes: {
              '0': {
                id: champ_multiple_drop_down_list.id,
                value: ['', 'un', 'deux']
              }
            }
          }
        }
      end

      it {
        expect(dossier.reload.last_champ_private_updated_at).to eq(nil)
        expect(response).to redirect_to(annotations_privees_instructeur_dossier_path(dossier.procedure, dossier))
      }
    end
  end

  describe "#telecharger_pjs" do
    subject do
      get :telecharger_pjs, params: {
        procedure_id: procedure.id,
        dossier_id: dossier.id
      }
    end

    context 'when zip download is disabled through flipflop' do
      it 'is forbidden' do
        subject
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "#delete_dossier" do
    subject do
      patch :delete_dossier, params: {
        procedure_id: procedure.id,
        dossier_id: dossier.id
      }
    end

    before do
      dossier.passer_en_instruction(instructeur)
    end

    context 'just before delete the dossier, the operation must be equal to 2' do
      before do
        dossier.accepter!(instructeur, 'le dossier est correct')
      end

      it 'has 2 operations logs before deletion' do
        expect(DossierOperationLog.where(dossier_id: dossier.id).count).to eq(2)
      end
    end

    context 'when the instructeur want to delete a dossier with a decision' do
      before do
        dossier.accepter!(instructeur, "le dossier est correct")
        allow(DossierMailer).to receive(:notify_instructeur_deletion_to_user).and_return(double(deliver_later: nil))
        subject
      end

      it 'deletes previous logs and add a suppression log' do
        expect(DossierOperationLog.where(dossier_id: dossier.id).count).to eq(3)
        expect(DossierOperationLog.where(dossier_id: dossier.id).last.operation).to eq('supprimer')
      end

      it 'send an email to the user' do
        expect(DossierMailer).to have_received(:notify_instructeur_deletion_to_user).with(DeletedDossier.where(dossier_id: dossier.id).first, dossier.user.email)
      end

      it 'add a record into deleted_dossiers table' do
        expect(DeletedDossier.where(dossier_id: dossier.id).count).to eq(1)
        expect(DeletedDossier.where(dossier_id: dossier.id).first.revision_id).to eq(dossier.revision_id)
        expect(DeletedDossier.where(dossier_id: dossier.id).first.user_id).to eq(dossier.user_id)
        expect(DeletedDossier.where(dossier_id: dossier.id).first.groupe_instructeur_id).to eq(dossier.groupe_instructeur_id)
      end

      it 'discard the dossier' do
        expect(dossier.reload.hidden_at).not_to eq(nil)
      end
    end

    context 'when the instructeur want to delete a dossier without a decision' do
      before do
        subject
      end

      it 'does not delete the dossier' do
        expect { dossier.reload }.not_to raise_error # A deleted dossier would raise an ActiveRecord::RecordNotFound
      end

      it 'does not add a record into deleted_dossiers table' do
        expect(DeletedDossier.where(dossier_id: dossier.id).count).to eq(0)
      end
    end
  end
end
