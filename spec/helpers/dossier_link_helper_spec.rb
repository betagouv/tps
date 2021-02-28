describe DossierLinkHelper do
  describe "#dossier_linked_path" do
    context "when no access as a instructeur" do
      let(:instructeur) { create(:instructeur) }
      let(:dossier) { create(:dossier) }

      it { expect(helper.dossier_linked_path(instructeur, dossier)).to be_nil }
    end

    context "when no access as a user" do
      let(:user) { create(:user) }
      let(:dossier) { create(:dossier) }

      it { expect(helper.dossier_linked_path(user, dossier)).to be_nil }
    end

    context "when access as instructeur" do
      let(:procedure) { create(:procedure, :routee) }
      let(:dossier) { create(:dossier, groupe_instructeur: procedure.groupe_instructeurs.last) }
      let(:instructeur) { create(:instructeur) }

      before { procedure.groupe_instructeurs.last.instructeurs << instructeur }

      it { expect(helper.dossier_linked_path(instructeur, dossier)).to eq(instructeur_dossier_path(dossier.procedure, dossier)) }
    end

    context "when access as expert" do
      let(:dossier) { create(:dossier) }
      let(:instructeur) { create(:instructeur) }
      let(:expert) { create(:expert) }
      let!(:experts_procedure) { ExpertsProcedure.create(expert: expert, procedure: dossier.procedure) }
      let!(:avis) { create(:avis, dossier: dossier, claimant: instructeur, experts_procedure: experts_procedure) }
      it { expect(helper.dossier_linked_path(expert, dossier)).to eq(expert_avis_path(avis.dossier.procedure, avis)) }
    end

    context "when access as user" do
      let(:dossier) { create(:dossier) }
      let(:user) { create(:user) }

      before { dossier.user = user }

      it { expect(helper.dossier_linked_path(user, dossier)).to eq(dossier_path(dossier)) }
    end
  end
end
