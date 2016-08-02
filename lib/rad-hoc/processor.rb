require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

class RadHoc::Processor
  FILTER_OPERATORS = {"exactly" => :eq,
                      "less_than" => :lt,
                      "greater_than" => :gt
  }

  attr_accessor :scopes

  def initialize(spec_yaml, scopes = [])
    @query_spec = YAML.safe_load(spec_yaml)
    @scopes = scopes
  end

  def run_raw
    ActiveRecord::Base.connection.execute(construct_query.to_sql)
  end

  def run
    results = ActiveRecord::Base.connection.exec_query(construct_query.to_sql)
    linked = linked_keys.reduce([]) do |acc,key|
      chain = to_association_chain(key)
      acc << [key, model_for_association_chain(chain)]
    end

    {
      data: label_rows(cast_values(results)),
      labels: labels,
      linked: linked
    }
  end

  # Does no data extraction but provides row_fetcher to get values
  def run_as_activerecord
    row_fetcher = lambda do |row|
      fields.keys.map do |key|
        split_key(key).reduce(row, :send)
      end
    end
    {data: construct_query(includes: true), labels: labels, row_fetcher: row_fetcher}
  end

  def add_filter(key, type, value)
    constraints = filters[key]
    if !constraints
      constraints = {}
      @filters[key] = constraints
    end
    constraints[type] = value
    self
  end

  def validate
    [
      # Presence validations
      validation(:contains_table, "table must be defined", !table_name.nil?),
      # Type validations
      validation(:fields_is_hash, "fields must be a map", fields.class == Hash),
      validation(:filters_is_hash, "filters must be a map", filters.class == Hash)
    ].reduce([]) do |acc, validation|
      if validation[:valid]
        acc
      else
        acc.push({name: validation[:name], message: validation[:message]})
      end
    end
  end

  # Query Information
  def all_models
    models(all_keys.map(&method(:to_association_chain)))
  end

  def all_cols
    all_keys.map(&method(:key_to_col))
  end

  def table_name
    @query_spec['table']
  end

  private
  # Query prep methods
  def construct_query(includes: false)
    project(
      prepare_sorts(prepare_filters(
        joins(base_relation, includes: includes)
      ))
    )
  end

  def apply_scopes(query)
    @scopes.reduce(query) do |q, scope|
      scope.reduce(q) do |q, (scope_name, args)|
        if q.respond_to? scope_name
          q.send(scope_name, *args)
        else
          q
        end
      end
    end
  end

  def project(query)
    cols = data_keys.map &method(:key_to_col)
    query.select(cols)
  end

  def prepare_filters(query)
    filters.reduce(query) do |q, (key, constraints)|
      col = key_to_col(key)

      constraints.reduce(q) do |q,(type, value)|
        q.where(generate_filter(col, type, value))
      end
    end
  end

  def generate_filter(col, type, value)
    case type
    when 'starts_with'
      col.matches(value + '%')
    when 'ends_with'
      col.matches('%' + value)
    when 'contains'
      col.matches('%' + value + '%')
    else
      col.send(FILTER_OPERATORS[type], Arel::Nodes::Quoted.new(value))
    end
  end

  def prepare_sorts(query)
    sorts.reduce(query) do |q, sort|
      key, sort_type_s = sort.first
      col = key_to_col(key)
      sort_type = sort_type_s.to_sym

      q.order(col.send(sort_type))
    end
  end

  def joins(query, includes: false)
    association_chains = all_keys.map(&method(:to_association_chain))
    joins_hashes = association_chains.map do |association_chain|
      association_chain.reverse.reduce({}) do |join_hash, association_name|
        {association_name => join_hash}
      end
    end
    joined_query = query.joins(joins_hashes)
    if includes
      joined_query = joined_query.includes(joins_hashes)
    end

    # Apply scopes for all joined tables
    models(association_chains).reduce(joined_query) do |q, model|
      q.merge(apply_scopes(model).all)
    end
  end

  # Key handling helper methods
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

  # Methods for working with association chains
  def to_association_chain(key)
    init(split_key(key))
  end

  def model_for_association_chain(associations)
    if associations.empty?
      base_relation
    else
      reflections(associations).last.klass
    end
  end

  def reflections(association_chain)
    _, reflections = association_chain.reduce([base_relation, []]) do |acc, association_name|
      klass, reflections = *acc
      reflection = klass.reflect_on_association(association_name)
      raise ArgumentError, "Invalid association: #{association_name}" unless reflection
      [reflection.klass, reflections.push(reflection)]
    end
    reflections
  end

  # A list of all models accessed in an association chain
  def models(association_chains)
    [base_relation] + association_chains.map(&method(:reflections)).flatten(1).uniq.map(&:klass)
  end

  # Validation helper functions
  def validation(name, message, value)
    {name: name, message: message, valid: value}
  end

  # Post-Processing Methods
  # Associate column names with data
  def label_rows(rows)
    keys = data_keys
    rows.map do |row|
      keys.zip(row).to_h
    end
  end

  # Make sure values are of the correct type
  def cast_values(results)
    casters = data_keys.map do |key|
      field, associations = from_key(key)
      model_for_association_chain(associations).type_for_attribute(field)
    end
    results.rows.map do |row|
      casters.zip(row).map { |(caster, value)|
        caster.type_cast_from_database(value)
      }
    end
  end

  # Returns the lablels for each selected key
  def labels
    fields.reduce({}) do |acc, (key, options)|
      label = options && options['label'] || split_key(key).last.titleize
      acc.merge(key => label)
    end
  end

  # Returns an array of keys that were marked "link: true"
  def linked_keys
    @linked_keys ||= fields.reduce([]) do |acc, (key, options)|
      if options && options['link']
        acc << key
      else
        acc
      end
    end
  end

  # Memoized information
  def table
    @table ||= Arel::Table.new(table_name)
  end

  def fields
    @fields ||= @query_spec['fields'] || {}
  end

  def filters
    @filters ||= @query_spec['filter'] || {}
  end

  def sorts
    @sorts ||= @query_spec['sort'] || []
  end

  def all_keys
    fields.keys + filters.keys + sorts.map { |f| f.keys.first }
  end

  def data_keys
    if !@data_keys
      selected_keys = fields.keys
      id_keys = []
      selected_keys.map(&method(:to_association_chain)).uniq.each do |chain|
        id_keys << (chain + ['id']).join('.')
      end

      @data_keys = selected_keys + (id_keys - selected_keys)
    end
    @data_keys
  end

  def base_relation
    table.name.classify.constantize
  end
end
