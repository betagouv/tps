describe 'instructeurs/shared/avis/_list.html.haml', type: :view do
  before { view.extend DossierHelper }

  subject { render 'instructeurs/shared/avis/list.html.haml', avis: avis, avis_seen_at: seen_at, current_instructeur: instructeur }

  let(:instructeur) { create(:instructeur) }
  let(:expert) { create(:expert) }
  let!(:dossier) { create(:dossier) }
  let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: dossier.procedure) }
  let(:avis) { [create(:avis, claimant: instructeur, experts_procedure: experts_procedure)] }
  let(:seen_at) { avis.first.created_at + 1.hour }

  it { is_expected.to have_text(avis.first.introduction) }
  it { is_expected.not_to have_css(".highlighted") }

  context 'with a seen_at before avis created_at' do
    let(:seen_at) { avis.first.created_at - 1.hour }

    it { is_expected.to have_css(".highlighted") }
  end

  context 'with an answer' do
    let(:avis) { [create(:avis, :with_answer, claimant: instructeur, experts_procedure: experts_procedure)] }

    it 'renders the answer formatted with newlines' do
      expect(subject).to include(simple_format(avis.first.answer))
    end
  end
end
