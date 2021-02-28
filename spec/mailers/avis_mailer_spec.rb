RSpec.describe AvisMailer, type: :mailer do
  describe '.avis_invitation' do
    let(:claimant) { create(:instructeur) }
    let(:expert) { create(:expert) }
    let(:dossier) { create(:dossier) }
    let(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: dossier.procedure) }
    let(:avis) { Avis.create(dossier: dossier, claimant: claimant, experts_procedure: experts_procedure, introduction: 'intro') }

    subject { described_class.avis_invitation(avis) }

    it { expect(subject.subject).to eq("Donnez votre avis sur le dossier nº #{avis.dossier.id} (#{avis.dossier.procedure.libelle})") }
    it { expect(subject.body).to have_text("Vous avez été invité par\r\n#{avis.claimant.email}\r\nà donner votre avis sur le dossier nº #{avis.dossier.id} de la démarche :\r\n#{avis.dossier.procedure.libelle}") }
    it { expect(subject.body).to include(avis.introduction) }
    it { expect(subject.body).to include(instructeur_avis_url(avis.dossier.procedure.id, avis)) }

    context 'when the recipient is not already registered' do
      it { expect(subject.body).to include(sign_up_expert_avis_url(avis.dossier.procedure.id, avis.id, avis.expert.email)) }
    end
  end
end
