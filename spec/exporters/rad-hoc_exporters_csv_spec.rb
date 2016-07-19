require 'spec_helper'

describe RadHoc::Exporters::CSV do
  describe "#export" do
    it "can export a simple csv with a heading" do
      track1 = create(:track)
      track2 = create(:track, title: "Some Other Title")

      result = RadHoc::Exporters::CSV.new(from_yaml('simple.yaml').run).export

      line1, line2, line3 = result.split("\n")
      expect(line1).to include "Title"
      expect(line1).to include "Id"

      expect(line2).to include track1.id.to_s
      expect(line3).to include track2.id.to_s

      expect(line2).to include track1.title
      expect(line3).to include track2.title
    end

    it "omits headings when asked to" do
      create(:track)

      result = RadHoc::Exporters::CSV.new(
        from_yaml('simple.yaml').run, headings: false
      ).export

      expect(result.split("\n").length).to eq 1
    end
  end
end
