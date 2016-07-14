require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

class RadHoc
  def initialize(spec_yaml)
    @query_spec = YAML.load(spec_yaml)
  end

  def run_raw
    ActiveRecord::Base.connection.execute(constructed_query.to_sql)
  end

  def run
    results = ActiveRecord::Base.connection.exec_query(constructed_query.to_sql)

    {data: label_rows(results),
     labels: labels
    }
  end

  private
  def constructed_query
    project(prepare_filters(joins(table)))
  end

  def project(query)
    cols = fields.keys.map &method(:key_to_col)
    query.project(cols)
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
    filters = {"exactly" => :eq}
    col.send(filters[type], Arel::Nodes::Quoted.new(value))
  end

  def joins(query)
    keys = fields.keys + filters.map { |f| f.keys.first }
    associations = keys.map { |key| init(split_key(key)).unshift(table.name) }
    joins = associations.map(&method(:group2)).flatten(1).uniq
    joins.reduce(query) do |q, join|
      base_name, join_name = *join

      base_table = Arel::Table.new(base_name.pluralize)
      join_table = Arel::Table.new(join_name.pluralize)

      q.join(join_table).on(base_table[join_name.foreign_key].eq(join_table[:id]))
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

  # Associate column names with data
  def label_rows(results)
    keys = fields.keys
    results.rows.map do |row|
      keys.zip(row).to_h
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
end
