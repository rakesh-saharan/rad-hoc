require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

require 'rad-hoc/validator'
require 'rad-hoc/spec'

class RadHoc::Processor
  FILTER_OPERATORS = {"exactly" => :eq,
                      "less_than" => :lt,
                      "greater_than" => :gt
  }

  attr_accessor :scopes, :merge

  def initialize(spec_yaml, scopes = [], merge = {})
    @spec_yaml = spec_yaml
    @scopes = scopes
    @merge = merge
  end

  def run_raw
    ActiveRecord::Base.connection.execute(construct_query.to_sql)
  end

  def run
    results = ActiveRecord::Base.connection.exec_query(construct_query.to_sql)
    linked = linked_keys.reduce([]) do |acc,key|
      chain = s.to_association_chain(key)
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
      s.fields.keys.map do |key|
        s.split_key(key).reduce(row, :send)
      end
    end
    {data: construct_query(includes: true), labels: labels, row_fetcher: row_fetcher}
  end

  def validate
    RadHoc::Validator.new(nil_fill_s).validate
  end

  # Query Information
  def all_models
    spec = nil_fill_s
    spec.models(spec.all_keys.map(&spec.method(:to_association_chain)))
  end

  def all_cols
    spec = nil_fill_s
    spec.all_keys.map(&spec.method(:key_to_col))
  end

  def table_name
    nil_fill_s.table_name
  end

  private
  # Query prep methods
  def construct_query(includes: false)
    project(
      prepare_sorts(prepare_filters(
        joins(s.base_relation, includes: includes)
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
    cols = data_keys.map &s.method(:key_to_col)
    query.select(cols)
  end

  def prepare_filters(query)
    s.filters.reduce(query) do |q, (key, constraints)|
      col = s.key_to_col(key)

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
    s.sorts.reduce(query) do |q, sort|
      key, sort_type_s = sort.first
      col = s.key_to_col(key)
      sort_type = sort_type_s.to_sym

      q.order(col.send(sort_type))
    end
  end

  def joins(query, includes: false)
    association_chains = s.all_keys.map(&s.method(:to_association_chain))
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
    s.models(association_chains).reduce(joined_query) do |q, model|
      q.merge(apply_scopes(model).all)
    end
  end

  def model_for_association_chain(associations)
    if associations.empty?
      s.base_relation
    else
      s.reflections(associations).last.klass
    end
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
      field, associations = s.from_key(key)
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
    s.fields.reduce({}) do |acc, (key, options)|
      label = options && options['label'] || s.split_key(key).last.titleize
      acc.merge(key => label)
    end
  end

  # Returns an array of keys that were marked "link: true"
  def linked_keys
    @linked_keys ||= s.fields.reduce([]) do |acc, (key, options)|
      if options && options['link']
        acc << key
      else
        acc
      end
    end
  end

  def data_keys
    if !@data_keys
      selected_keys = s.fields.keys
      id_keys = []
      selected_keys.map(&s.method(:to_association_chain)).uniq.each do |chain|
        id_keys << (chain + ['id']).join('.')
      end

      @data_keys = selected_keys + (id_keys - selected_keys)
    end
    @data_keys
  end

  def s
    @s ||= RadHoc::Spec.new(@spec_yaml, @merge, false)
  end

  def nil_fill_s
    @nil_fill_s ||= RadHoc::Spec.new(@spec_yaml, {}, true)
  end
end
