require 'csv'

class RadHoc::Exporters::CSV
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
        csv << row.values
      end
    end
  end
end
