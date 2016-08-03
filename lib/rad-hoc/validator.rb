class RadHoc::Validator
  def initialize(s)
    @s = s
  end

  def validate
    validations = [
      # Presence validations
      validation(:contains_table, "table must be defined", !@s.table_name.nil?),
      # Type validations
      validation(:fields_is_hash, "fields must be a map", @s.fields.class == Hash),
      validation(:filters_is_hash, "filters must be a map", @s.filters.class == Hash)
    ]
    @query_spec = nil
    validations.reduce([]) do |acc, validation|
      if validation[:valid]
        acc
      else
        acc.push({name: validation[:name], message: validation[:message]})
      end
    end
  end

  def validation(name, message, value)
    {name: name, message: message, valid: value}
  end
end
