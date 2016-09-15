class RadHoc::Spec
  # From Psych's safe_load
  def initialize(spec_yaml, merge, fill_nil)
    result = YAML.parse(spec_yaml, nil)
    raise ArgumentError, "Bad Spec (Psych could not parse YAML)" unless result

    class_loader = Psych::ClassLoader::Restricted.new([], [])
    scanner = Psych::ScalarScanner.new class_loader
    visitor = ToRubyWithMerge.new scanner, class_loader, merge, fill_nil

    @query_spec = visitor.accept result
  end

  # Helper methods
  def base_relation
    table.name.classify.constantize
  end

  def table
    @table ||= Arel::Table.new(table_name)
  end

  def reflections(association_chain)
    association_chain.reduce([]) do |kreflections, association|
      association_name, association_type = association.split('|')
      current = kreflections.last&.klass || base_relation
      reflection = current.reflect_on_association(association_name)
      raise ArgumentError, "Invalid association: #{association_name}" unless reflection
      if reflection.polymorphic?
        raise ArgumentError, "Must provide type for association: #{association_name}" unless association_type
        reflection_klass = association_type.constantize
      else
        reflection_klass = reflection.klass
      end
      kreflections.push(KReflection.new(current, reflection_klass, reflection))
    end
  end

  def klasses(association_chain)
    reflections(association_chain).map(&:klass)
  end

  # Key handling helper methods
  # From a table_1.table_2.column style key to [column, [table_1, table_2]]
  def from_key(key)
    s_key = key.split('.')
    [s_key.last, init(s_key)]
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
      klasses(associations).last.arel_table[col]
    end
  end

  def to_association_chain(key)
    init(split_key(key))
  end

  # A list of all models accessed in an association chain
  def models(association_chains)
    ([base_relation] + association_chains.map(&method(:klasses)).flatten(1)).uniq
  end

  # Memoized information
  def query_spec
    @query_spec ||= load_spec
  end

  def table_name
    query_spec['table']
  end

  def fields
    @fields ||= query_spec['fields']
  end

  def filters
    @filters ||= query_spec['filter']
  end

  def sorts
    @sorts ||= query_spec['sort']
  end

  def all_keys
    fields.keys + filters.keys + sorts.map { |f| f.keys.first }
  end
end

class ToRubyWithMerge < Psych::Visitors::ToRuby
  def initialize ss, class_loader, merge, fill_nil
    super(ss, class_loader)
    @fill_nil = fill_nil
    @st = merge
  end

  def visit_Psych_Nodes_Alias o
    if @fill_nil
      nil
    else
      @st.fetch(o.anchor) { raise Psych::BadAlias, "Unknown alias: #{o.anchor}" }
    end
  end
end

# Holds a reflection and it's class because the klass instance variable is not
# set for polymorphic associations
class KReflection < Struct.new(:base, :klass, :reflection)
end
