require 'spec_helper'
require 'json'

describe RadHoc::Exporters::JSON do
  describe "#export" do
    it "creates a json file that is identical to the result" do
      track1 = create(:track)
      track2 = create(:track, title: "Some Other Title")

      processor_result = from_yaml('simple.yaml').run
      result = RadHoc::Exporters::JSON.new(processor_result).export

      expect(JSON.load(result)).to eq processor_result.stringify_keys
    end
  end
end
