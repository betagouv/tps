RSpec.describe ExpertsProcedure, type: :model do
  describe '#invited_expert_emails' do
    let!(:procedure) { create(:procedure, :published) }
    let(:claimant) { create(:instructeur) }
    let(:expert) { create(:expert) }
    let(:expert2) { create(:expert) }
    let(:expert3) { create(:expert) }
    let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: procedure) }
    let(:experts_procedure2) { ExpertsProcedure.create(expert: expert2, procedure: procedure) }
    let(:experts_procedure3) { ExpertsProcedure.create(expert: expert3, procedure: procedure) }
    subject { procedure.experts_procedures }

    context 'when there is one dossier' do
      let!(:dossier) { create(:dossier, procedure: procedure) }

      context 'when a procedure has one avis and known instructeur' do
        let!(:avis) { create(:avis, dossier: dossier, claimant: claimant, experts_procedure: experts_procedure) }

        it { is_expected.to eq([experts_procedure]) }
        it { expect(procedure.experts.count).to eq(1) }
        it { expect(procedure.experts.first.email).to eq(expert.email) }
      end

      context 'when a dossier has 2 avis from the same expert' do
        let!(:avis) { create(:avis, dossier: dossier, experts_procedure: experts_procedure) }
        let!(:avis2) { create(:avis, dossier: dossier, experts_procedure: experts_procedure) }

        it { is_expected.to eq([experts_procedure]) }
        it { expect(procedure.experts.count).to eq(1) }
        it { expect(procedure.experts.first).to eq(expert) }
      end
    end

    context 'when there are two dossiers' do
      let!(:dossier) { create(:dossier, procedure: procedure) }
      let!(:dossier2) { create(:dossier, procedure: procedure) }

      context 'and each one has an avis from 3 different experts' do
        let!(:avis) { create(:avis, dossier: dossier, experts_procedure: experts_procedure) }
        let!(:avis2) { create(:avis, dossier: dossier2, experts_procedure: experts_procedure2) }
        let!(:avis3) { create(:avis, dossier: dossier2, experts_procedure: experts_procedure3) }

        it { is_expected.to match_array([experts_procedure, experts_procedure2, experts_procedure3]) }
        it { expect(procedure.experts.count).to eq(3) }
        it { expect(procedure.experts).to match_array([expert, expert2, expert3]) }
      end
    end
  end
end
