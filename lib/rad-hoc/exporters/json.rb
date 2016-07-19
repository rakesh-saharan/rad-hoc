require 'json'

class RadHoc::Exporters::JSON
  def initialize(processor_result)
    @result = processor_result
  end

  def export
    JSON.generate @result
  end
end
