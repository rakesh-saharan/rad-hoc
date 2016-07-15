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
    associations = keys.map { |key| init(split_key(key)).unshift(table.name) }
    joins = associations.map(&method(:group2)).flatten(1).uniq
    joins.reduce(query) do |q, join|
      base_name, join_name = *join

      base_table = Arel::Table.new(base_name.pluralize)
      join_table = Arel::Table.new(join_name.pluralize)

      q.joins(Arel::Nodes::InnerJoin.new(join_table, Arel::Nodes::On.new(base_table[join_name.foreign_key].eq(join_table[:id]))))
    end
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
      Arel::Table.new(associations.last.pluralize)[col]
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
      associations.unshift(table.name).last.classify.constantize.type_for_attribute(field)
    end
    results.rows.map do |row|
      casters.zip(row).map { |(caster, value)|
        caster.cast(value)
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
