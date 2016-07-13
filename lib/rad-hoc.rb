require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

class RadHoc
  def initialize(spec_yaml)
    @query_spec = YAML.load(spec_yaml)
  end

  def run_raw
    q = table
    q, fields = prepare_fields(q, [])
    q = q.project(fields.map {|field| field[:column]})
    ActiveRecord::Base.connection.execute(q.to_sql)
  end

  def run
    filtered, joined = prepare_filters(table, [])
    fielded, fields = prepare_fields(filtered, joined)
    selected = fielded.project(fields.map {|field| field[:column]})
    results = ActiveRecord::Base.connection.exec_query(selected.to_sql)

    {data: label_rows(results, fields),
     labels: generate_labels(fields)
    }
  end

  private
  def prepare_fields(q, joined)
    fields = @query_spec['fields'] || {'id' => nil}
    fields.reduce([q, [], []]) do |acc, (key,options)|
      q, fields, joined = *acc # Deconstruct accumulator
      field, associations = from_key(key)

      q, current_table, joined = joins(q, associations, joined)

      label = options && options['label'] || key.titleize

      field = {column: current_table[field], key: key, label: label}
      [q, fields.append(field), joined]
    end
  end

  def prepare_filters(q, joined)
    filters = @query_spec['filter'] || []
    filters.reduce([q, joined]) do |acc, filter|
      q, joined = *acc # Deconstruct accumulator
      field, associations = from_key(filter.keys.first)

      q, current_table, joined = joins(q, associations, joined)

      filtered_q = filter.values.first.reduce(q) do |acc,(type, value)|
        q.where(generate_filter(current_table, field, type, value))
      end
      [filtered_q, joined]
    end
  end

  def generate_filter(table, col, type, value)
    filters = {"exactly" => :eq}
    table[col].send(filters[type], value)
  end

  # Joins the tables we need to be able to access the field we want
  def joins(q, associations, joined)
    associations.reduce([q, table, joined]) do |acc,assoc|
      q, current_table, joined = *acc # Deconstruct accumulator

      join_table = Arel::Table.new(assoc.pluralize)
      joined_elem = [current_table, join_table].map &:name
      if !joined.include?(joined_elem) # Make sure that we haven't already joined this one
        [q.join(join_table).on(current_table[assoc.foreign_key].eq(join_table[:id])),
         join_table,
         joined << joined_elem
        ]
      else
        [q, join_table, joined]
      end
    end
  end

  # From a table_1.table_2.column style key to [column, [table_1, table_2]]
  def from_key(key)
    s = key.split('.')
    [s.last, s[0..-2]]
  end

  # Associate column names with data
  def label_rows(results, fields)
    keys = fields.map {|field| field[:key]}
    results.rows.map do |row|
      keys.zip(row).to_h
    end
  end

  def generate_labels(fields)
    fields.reduce({}) do |acc,field|
      acc.merge(field[:key] => field[:label])
    end
  end

  def table
    @table ||= Arel::Table.new(@query_spec['table'])
  end
end
