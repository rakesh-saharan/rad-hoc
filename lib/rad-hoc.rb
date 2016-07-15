require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

class RadHoc
  FILTER_OPERATORS = {"exactly" => :eq,
                      "less_than" => :lt,
                      "greater_than" => :gt
  }

  def initialize(spec_yaml)
    @query_spec = YAML.load(spec_yaml)
  end

  def run_raw
    ActiveRecord::Base.connection.execute(construct_query(default_relation).to_sql)
  end

  def run(relation = default_relation)
    query = construct_query(relation)
    results = ActiveRecord::Base.connection.exec_query(query.to_sql)

    {data: label_rows(cast_values(results)),
     labels: labels
    }
  end

  def add_filter(key, type, value)
    match = filters.select { |col, _| col == key }.first
    if !match
      match = {key => {}}
      filters << match
    end
    match[key][type] = value
    self
  end

  def validate
    validations = [
      # Presence validations
      validation(:contains_table, "table must be defined", !@query_spec['table'].nil?),
      # Type validations
      validation(:fields_is_hash, "fields must be a map", fields.class == Hash)
    ]

    validations.reduce({valid: true, errors: []}) do |acc, validation|
      if validation[:valid]
        acc
      else
        error = {name: validation[:name], message: validation[:message]}
        {valid: false, errors: acc[:errors].push(error)}
      end
    end
  end

  private
  def construct_query(from)
    project(prepare_filters(joins(from)))
  end

  def project(query)
    cols = fields.keys.map &method(:key_to_col)
    query.select(cols)
  end

  def prepare_filters(query)
    filters.reduce(query) do |q, filter|
      col = key_to_col(filter.keys.first)

      filter.values.first.reduce(q) do |q,(type, value)|
        q.where(generate_filter(col, type, value))
      end
    end
  end

  def generate_filter(col, type, value)
    col.send(FILTER_OPERATORS[type], Arel::Nodes::Quoted.new(value))
  end

  def joins(query)
    keys = fields.keys + filters.map { |f| f.keys.first }
    association_chains = keys.map { |key| init(split_key(key)) }
    joins_hashes = association_chains.map do |association_chain|
      association_chain.reverse.reduce({}) do |join_hash, association_name|
        {association_name => join_hash}
      end
    end
    query.joins(joins_hashes)
  end

  def reflections(association_chain)
    _, reflections = association_chain.reduce([default_relation, []]) do |acc, association_name|
      klass, reflections = *acc
      reflection = klass.reflect_on_association(association_name)
      [reflection.klass, reflections.push(reflection)]
    end
    reflections.uniq
  end

  # [1,2,3,4] -> [[1,2], [2,3], [3,4]]
  def group2(a)
    a.take(a.size - 1).zip(a.drop(1))
  end

  # From a table_1.table_2.column style key to [column, [table_1, table_2]]
  def from_key(key)
    s = key.split('.')
    [s.last, init(s)]
  end

  def init(a)
    a[0..-2]
  end

  def split_key(key)
    key.split('.')
  end

  def key_to_col(key)
    col, associations = from_key(key)
    if associations.empty?
      table[col]
    else
      # Use arel_attribute in rails 5
      reflections(associations).last.klass.arel_table[col]
    end
  end

  # Validation helper functions
  def validation(name, message, value)
    {name: name, message: message, valid: value}
  end

  # Associate column names with data
  def label_rows(rows)
    keys = fields.keys
    rows.map do |row|
      keys.zip(row).to_h
    end
  end

  def cast_values(results)
    casters = fields.keys.map do |key|
      field, associations = from_key(key)
      if associations.empty?
        default_relation.type_for_attribute(field)
      else
        reflections(associations).last.klass.type_for_attribute(field)
      end
    end
    results.rows.map do |row|
      casters.zip(row).map { |(caster, value)|
        caster.type_cast_from_database(value)
      }
    end
  end

  def labels
    fields.reduce({}) do |acc, (key, options)|
      label = options && options['label'] || split_key(key).last.titleize
      acc.merge(key => label)
    end
  end

  # Easy access to yaml nodes
  def table
    @table ||= Arel::Table.new(@query_spec['table'])
  end

  def fields
    @fields ||= @query_spec['fields'] || {'id' => nil}
  end

  def filters
    @filters ||= @query_spec['filter'] || []
  end

  def default_relation
    table.name.classify.constantize
  end
end
