require 'yaml'
require 'arel'
require 'active_support/core_ext/string/inflections'

require 'rad_hoc/validator'
require 'rad_hoc/spec'

class RadHoc::Processor
  FILTER_OPERATORS = {"exactly" => :eq,
                      "less_than" => :lt,
                      "greater_than" => :gt
  }

  attr_accessor :scopes, :merge

  def initialize(spec_yaml, rejected_tables = [], scopes = [], merge = {})
    @spec_yaml = spec_yaml
    @rejected_tables = rejected_tables
    @scopes = scopes
    @merge = merge
  end

  def run(options = {})
    results = ActiveRecord::Base.connection.exec_query(
      project(construct_query(**options)).to_sql
    )
    post_process(results)
  end

  def count(options = {})
    construct_query(**options).count
  end

  def validate
    RadHoc::Validator.new(nil_fill_s, @rejected_tables).validate
  end

  # Query Information
  def all_models
    nil_fill_s.all_models
  end

  def all_cols
    nil_fill_s.all_cols
  end

  def table_name
    nil_fill_s.table_name
  end

  private
  # Query prep methods
  def construct_query(offset: nil, limit: nil)
    apply_limit_offset(offset, limit,
      prepare_sorts(prepare_filters(
        joins(s.base_relation)
      ))
    )
  end

  def apply_limit_offset(offset, limit, query)
    query.offset(offset).limit(limit)
  end

  def apply_scopes(query)
    @scopes.reduce(query) do |q, scope|
      scope.reduce(q) do |q, (scope_name, args)|
        if q.respond_to? scope_name
          q.send(scope_name, *args)
        else
          raise ArgumentError, "scope #{scope_name} does not exist on #{q.to_s}"
        end
      end
    end
  end

  def project(query)
    cols = data_keys.map &s.method(:key_to_col)
    query.select(cols)
  end

  def prepare_filters(query)
    apply_ands(query, build_constraints(s.filters))
  end

  def apply_ands(query, ands)
    if ands.empty?
      query
    else
      query.where(Arel::Nodes::And.new(ands))
    end
  end

  def build_constraints(filters)
    constraints = filters.map do |key, value|
      case key
      when 'or'
        safe_node(build_constraints(value)) do |r|
          r[1..-1].reduce(r.first) do |acc,cond|
            acc.or(cond)
          end
        end
      when 'and'
        safe_node(build_constraints(value)) do |r|
          Arel::Nodes::And.new(r)
        end
      when 'not'
        safe_node(build_constraints(value)) do |r|
          Arel::Nodes::And.new(r).not
        end
      else
        col = s.key_to_col(key)

        constraints = value.reduce([]) do |acc, (type, value)|
          acc << generate_filter(col, type, value)
        end

        safe_node(constraints) do |r|
          Arel::Nodes::And.new(r)
        end
      end
    end
    constraints.compact
  end

  def safe_node(constraints)
    if constraints.empty?
      nil
    else
      yield constraints
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

  def joins(query)
    association_chains = s.all_keys.map(&s.method(:to_association_chain))
    rjoins = (association_chains.map do |association_chain|
      s.reflections(association_chain).map do |kreflection|
        fk = kreflection.reflection.foreign_key
        table = kreflection.base.arel_table
        join_table = kreflection.klass.arel_table

        where = if kreflection.reflection.polymorphic? then
                  table[kreflection.reflection.foreign_type].eq(kreflection.klass.to_s)
                end
        RestrictedJoin.new(
          where,
          Arel::Nodes::InnerJoin.new(join_table, Arel::Nodes::On.new(table[fk].eq(join_table[:id])))
        )
      end
    end).flatten(1)
    joined_query = apply_ands(query.joins(rjoins.map(&:join)), rjoins.map(&:where).compact)

    # Apply scopes for all joined tables
    s.models(association_chains).reduce(joined_query) do |q, model|
      q.merge(apply_scopes(model).all)
    end
  end

  def model_for_association_chain(associations)
    if associations.empty?
      s.base_relation
    else
      s.klasses(associations).last
    end
  end

  # Post-Processing Methods
  def post_process(results)
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
      label = options && options['label'] || default_label(key)
      acc.merge(key => label)
    end
  end
  
  def default_label(key)
    s.split_key(key).last(2).join(" ").titleize
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

  # We might want to make auto-selecting ids optional for exporters that don't
  # need the ids and just want to show the user what they selected
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

class RestrictedJoin < Struct.new(:where, :join)
end
