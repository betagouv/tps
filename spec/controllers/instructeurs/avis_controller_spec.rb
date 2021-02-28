describe Instructeurs::AvisController, type: :controller do
  context 'with a instructeur signed in' do
    render_views

    let(:now) { Time.zone.parse('01/02/2345') }
    let(:expert) { create(:expert) }
    let(:claimant) { create(:instructeur) }
    let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: procedure) }
    let(:instructeur) { create(:instructeur) }
    let(:procedure) { create(:procedure, :published, instructeurs: [instructeur]) }
    let(:dossier) { create(:dossier, :en_construction, procedure: procedure) }
    let!(:avis) { Avis.create(dossier: dossier, claimant: instructeur, experts_procedure: experts_procedure) }
    let!(:avis_without_answer) { Avis.create(dossier: dossier, claimant: claimant, experts_procedure: experts_procedure) }

    before { sign_in(instructeur.user) }

    describe "#revoker" do
      before do
        patch :revoquer, params: { procedure_id: procedure.id, id: avis.id }
      end

      it "revoke the dossier" do
        expect(flash.notice).to eq("#{avis.expert.email} ne peut plus donner son avis sur ce dossier.")
      end
    end

    describe 'revive' do
      before do
        allow(AvisMailer).to receive(:avis_invitation).and_return(double(deliver_later: nil))
      end

      it 'sends a reminder to the expert' do
        get :revive, params: { procedure_id: procedure.id, id: avis.id }
        expect(AvisMailer).to have_received(:avis_invitation).once.with(avis)
        expect(flash.notice).to eq("Un mail de relance a été envoyé à #{avis.expert.email}")
      end
    end
  end
end
