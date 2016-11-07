class RadHoc::Validator
  def initialize(s, rejected_tables)
    @s = s
    @rejected_tables = rejected_tables
  end

  def validate
    validations = []

    # Presence validations
    validations.push(validation(:contains_table, "table must be defined")) if @s.table_name.nil?
    validations.push(validation(:contains_fields, "fields must be defined")) if @s.fields.nil?
    validations.push(validation(:contains_filter, "filter must be defined")) if @s.filters.nil?
    validations.push(validation(:contains_sort, "sort must be defined")) if @s.sorts.nil?

    # Type validations
    validations.push(validation(:fields_is_hash, "fields must be a map")) unless @s.fields.class == Hash
    validations.push(validation(:filter_is_hash, "filters must be a map")) unless @s.filters.class == Hash

    if validations.empty?
      # Check if any tables are "rejected tables"
      @s.all_models.each do |model|
        if @rejected_tables.include?(model.table_name)
          validations.push(validation(:valid_table, "model #{model.name} is not allowed"))
        end
      end

      # Ensure data types are defined for all fields
      @s.fields.each do |_,options|
        if options && options["type"]
          field_type = options["type"]

          unless ["integer", "string", "datetime", "boolean", "text", "decimal", "float", "date"].include?(field_type)
            validations.push(validation(:valid_data_type, "data type #{field_type} is not implemented"))
          end

        else
          validations.push(validation(:has_data_type, "fields must have data types"))
        end
      end
    end

    validations.reduce([]) do |acc, validation|
      acc.push({name: validation[:name], message: validation[:message]})
    end
  end

  def validation(name, message)
    {name: name, message: message}
  end
end
