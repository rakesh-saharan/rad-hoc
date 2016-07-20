require 'spec_helper'

describe RadHoc::Exporters::XLSX do
  describe "#export" do
    it "creates a file with content" do
      track1 = create(:track)

      result = RadHoc::Exporters::XLSX.new(from_yaml('simple.yaml').run).export

      # There has got to be a better way to test this
      expect(result.length).to be > 2000
    end
  end
end
