require 'axlsx'

class RadHoc::Exporters::XLSX
  def initialize(rad_hoc_result, headings: true)
    @result = rad_hoc_result
    @headings = headings
  end

  def export
    p = Axlsx::Package.new
    p.workbook.add_worksheet(name: "Results") do |sheet|
      if @headings
        sheet.add_row @result[:labels].values
      end
      @result[:data].each do |row|
        sheet.add_row row.values
      end
    end
    p.to_stream
  end
end
