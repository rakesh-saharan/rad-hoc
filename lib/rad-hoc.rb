require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

class RadHoc
  def initialize(spec_yaml)
    @query_spec = YAML.load(spec_yaml)
  end

  def run_raw
    q = table
    q, select_fields = fields(q)
    q = q.project(select_fields.map {|field| field[:column]})
    ActiveRecord::Base.connection.execute(q.to_sql)
  end

  def run
    q = table
    q, select_fields = fields(q)
    q = q.project(select_fields.map {|field| field[:column]})
    results = ActiveRecord::Base.connection.exec_query(q.to_sql)

    # Associate column names with data
    keys = select_fields.map {|field| field[:key]}
    data = results.rows.map do |row|
      keys.zip(row).to_h
    end
    {data: data}
  end

  private
  def query
  end

  # Currently handles the joins, but that will need to be pulled out
  # in order to handle joins for other (filtering, aggregate data, etc)
  # purposes
  def fields(q)
    @query_spec['fields'].keys.reduce([q, [], []]) do |acc,key|
      q, fields, joined = *acc # Deconstruct accumulator

      assocs = key.split('.') # Get belongs_to associations by singluar names
      field = assocs.pop      # and pop the name of the actual field

      # Joins the tables we need to be able to access the field we want
      q, current_table, joined = assocs.reduce([q, table, joined]) do |acc,assoc|
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

      [q,
       fields.append({
        column: current_table[field], key: key, label: key.titleize
       }),
       joined
      ]
    end
  end

  def table
    @table ||= Arel::Table.new(@query_spec['table'])
  end
end
