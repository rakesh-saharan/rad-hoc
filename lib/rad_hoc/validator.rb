class RadHoc::Validator
  def initialize(s)
    @s = s
  end

  def validate
    validations = [
      # Presence validations
      validation(:contains_table, "table must be defined", !@s.table_name.nil?),
      validation(:contains_fields, "fields must be defined", !@s.fields.nil?),
      validation(:contains_filter, "filter must be defined", !@s.filters.nil?),
      validation(:contains_sort, "sort must be defined", !@s.sorts.nil?),
      # Type validations
      validation(:fields_is_hash, "fields must be a map", @s.fields.class == Hash),
      validation(:filter_is_hash, "filters must be a map", @s.filters.class == Hash)
    ]

    if @s.fields && @s.fields.class == Hash
      @s.fields.each do |field|
        if field[1] && field[1]["type"]
          field_type = field[1]["type"]

          unless ["integer", "string", "datetime", "boolean", "text", "decimal", "float", "date"].include?(field_type)
            validations.push(validation(:valid_data_type, "data type #{field_type} is not implemented", false))
          end

        else
          validations.push(validation(:has_data_type, "fields must have data types", false))
        end
      end
    end

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
