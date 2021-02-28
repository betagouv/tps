describe 'shared/dossiers/champs.html.haml', type: :view do
  let(:instructeur) { create(:instructeur) }
  let(:demande_seen_at) { nil }

  before do
    view.extend DossierHelper
    view.extend DossierLinkHelper
    allow(view).to receive(:current_instructeur).and_return(instructeur)
  end

  subject { render 'shared/dossiers/champs.html.haml', champs: champs, dossier: dossier, demande_seen_at: demande_seen_at, profile: nil }

  context "there are some champs" do
    let(:dossier) { create(:dossier) }
    let(:champ1) { create(:champ_checkbox, dossier: dossier, value: "on") }
    let(:champ2) { create(:champ_header_section, dossier: dossier, value: "Section") }
    let(:champ3) { create(:champ_explication, dossier: dossier, value: "mazette") }
    let(:champ4) { create(:champ_dossier_link, dossier: dossier, value: dossier.id) }
    let(:champ5) { create(:champ_textarea, dossier: dossier, value: "Some long text in a textarea.") }
    let(:champs) { [champ1, champ2, champ3, champ4, champ5] }

    it "renders titles and values of champs" do
      expect(subject).to include(champ1.libelle)
      expect(subject).to include(champ1.value)

      expect(subject).to have_css(".header-section")
      expect(subject).to include(champ2.libelle)

      expect(subject).to include(dossier.text_summary)

      expect(subject).to include(champ5.libelle)
      expect(subject).to include(champ5.libelle)
    end

    it "doesn't render explication champs" do
      expect(subject).not_to include(champ3.libelle)
      expect(subject).not_to include(champ3.value)
    end

    context "with auto-link" do
      let(:champ1) { create(:champ_text, value: "https://github.com/tchak") }
      let(:champ2) { create(:champ_textarea, value: "https://github.com/LeSim") }
      let(:link1) { '<a href="https://github.com/tchak" target="_blank" rel="noopener">https://github.com/tchak</a>' }
      let(:link2) { '<a href="https://github.com/LeSim" target="_blank" rel="noopener">https://github.com/LeSim</a>' }

      it "render links" do
        expect(subject).to include(link1)
        expect(subject).to include(link2)
      end
    end
  end

  context "with a routed procedure" do
    let(:procedure) do
      create(:procedure,
        :routee,
        routing_criteria_name: 'departement')
    end
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:champs) { [] }

    it "does not render the routing criteria name and its value" do
      expect(subject).not_to include(procedure.routing_criteria_name)
      expect(subject).not_to include(dossier.procedure.defaut_groupe_instructeur.label)
    end

    context "with selected groupe instructeur" do
      before do
        dossier.groupe_instructeur = dossier.procedure.defaut_groupe_instructeur
      end

      it "renders the routing criteria name and its value" do
        expect(subject).to include(procedure.routing_criteria_name)
        expect(subject).to include(dossier.groupe_instructeur.label)
      end
    end

    context "with seen_at" do
      let(:dossier) { create(:dossier) }
      let(:nouveau_groupe_instructeur) { create(:groupe_instructeur, procedure: dossier.procedure) }
      let(:champ1) { create(:champ_checkbox, dossier: dossier, value: "on") }
      let(:champs) { [champ1] }

      context "with a demande_seen_at after groupe_instructeur_updated_at" do
        let(:demande_seen_at) { dossier.groupe_instructeur_updated_at + 1.hour }

        it "expect to not highlight new group instructeur label" do
          dossier.assign_to_groupe_instructeur(nouveau_groupe_instructeur)
          expect(subject).not_to have_css(".highlighted")
        end
      end

      context "with a demande_seen_at before groupe_instructeur_updated_at" do
        let(:demande_seen_at) { dossier.groupe_instructeur_updated_at - 1.hour }

        it "expect to not highlight new group instructeur label" do
          dossier.assign_to_groupe_instructeur(nouveau_groupe_instructeur)
          expect(subject).to have_css(".highlighted")
        end
      end
    end
  end

  context "with a dossier champ, but we are not authorized to acces the dossier" do
    let(:dossier) { create(:dossier) }
    let(:champ) { create(:champ_dossier_link, dossier: dossier, value: dossier.id) }
    let(:champs) { [champ] }

    it { is_expected.not_to have_link("Dossier nº #{dossier.id}") }
    it { is_expected.to include("Dossier nº #{dossier.id}") }
    it { is_expected.to include(dossier.text_summary) }
  end

  context "with a dossier_link champ but without value" do
    let(:dossier) { create(:dossier) }
    let(:champ) { create(:champ_dossier_link, dossier: dossier, value: nil) }
    let(:champs) { [champ] }

    it { is_expected.to include("Pas de dossier associé") }
  end

  context "with seen_at" do
    let(:dossier) { create(:dossier) }
    let(:champ1) { create(:champ_checkbox, dossier: dossier, value: "on") }
    let(:champs) { [champ1] }

    context "with a demande_seen_at after champ updated_at" do
      let(:demande_seen_at) { champ1.updated_at + 1.hour }

      it { is_expected.not_to have_css(".highlighted") }
    end

    context "with a demande_seen_at after champ updated_at" do
      let(:demande_seen_at) { champ1.updated_at - 1.hour }

      it { is_expected.to have_css(".highlighted") }
    end
  end
end
