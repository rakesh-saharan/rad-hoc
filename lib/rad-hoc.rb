require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

class RadHoc
  def initialize(spec_yaml)
    @query_spec = YAML.load(spec_yaml)
  end

  def run_raw
    q = table
    q, fields = prepare_fields(q)
    q = q.project(fields.map {|field| field[:column]})
    ActiveRecord::Base.connection.execute(q.to_sql)
  end

  def run
    q = table
    q, fields = prepare_fields(q)
    q = q.project(fields.map {|field| field[:column]})
    results = ActiveRecord::Base.connection.exec_query(q.to_sql)

    {data: label_rows(results, fields),
     labels: generate_labels(fields)
    }
  end

  private
  def prepare_fields(q)
    @query_spec['fields'].reduce([q, [], []]) do |acc, (key,options)|
      q, fields, joined = *acc # Deconstruct accumulator
      field, associations = from_key(key)

      q, current_table, joined = joins(q, associations, joined)

      label = options && options['label'] || key.titleize

      field = {column: current_table[field], key: key, label: label}
      [q, fields.append(field), joined]
    end
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
