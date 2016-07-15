ActiveRecord::Schema.define do
  create_table :albums do |table|
    table.column :title, :string
    table.column :performer_id, :integer
    table.column :owner_id, :integer
    table.column :released_on, :date
  end

  create_table :tracks do |table|
    table.column :album_id, :integer
    table.column :track_number, :integer
    table.column :title, :string
  end

  create_table :performers do |table|
    table.column :title, :string
    table.column :name, :string
  end

  create_table :records do |table|
    table.column :name, :string
  end
end
