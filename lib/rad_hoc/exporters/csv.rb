require 'csv'
require 'rad_hoc/helpers'

class RadHoc::Exporters::CSV
  include RadHoc::Helpers::Export

  def initialize(rad_hoc_result, headings: true)
    @result = rad_hoc_result
    @headings = headings
  end

  def export
    CSV.generate do |csv|
      if @headings
        csv << @result[:labels].values
      end
      @result[:data].each do |row|
        csv << drop_ids(row.values)
      end
    end
  end
end
