describe DeletedDossier do
  let(:deleted_dossier) { create(:deleted_dossier) }

  describe 'with discarded procedure' do
    before do
      deleted_dossier.procedure.discard!
      deleted_dossier.reload
    end

    it { expect(deleted_dossier.procedure).not_to be_nil }
  end
end
