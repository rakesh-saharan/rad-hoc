# Rad hoc
[![Code Climate](https://codeclimate.com/github/radicalbear/rad-hoc/badges/gpa.svg)](https://codeclimate.com/github/radicalbear/rad-hoc)
[![Issue Count](https://codeclimate.com/github/radicalbear/rad-hoc/badges/issue_count.svg)](https://codeclimate.com/github/radicalbear/rad-hoc/issues)

Library for custom reports generated from YAML query specifications

## Usage
To use RadHoc, you must have an established connection with the database through ActiveRecord

The `RadHoc` object is initialized with a YAML string:
```ruby
processor = RadHoc.new(
  <<-EOF
  table: companies
  fields:
    name:
  EOF
)
```

Use `#validate` to check whether the specification is valid (not yet fully implemented):
```ruby
valid = processor.validate
```
If the spec is valid, `#validate` will return an Array of errors which contains information about why the spec is invalid.

To run the query, use the `#run` method:
```ruby
results = processor.run
```
This returns a hash:
- `results[:data]`: an Array of Hashes with the selected values indexed by field key 
  - `[{"name" => "Some Company"}]` if there was one company with the name "Some Company" in the DB
- `results[:labels]`: a labels Hash for the field keys
  - `{'name' => 'Name'}` in this case
- `results[:linked]`: an array of pairs with the keys and models of fields marked `link: true`

You can pass in an ActiveRecord relation if you want to do some filtering before running the query. It will error if the specification is not valid, so check with `#validate` before using `#run` (once it's implemented).

## Supported Filters
* exactly
* less_than
* greater_than
* starts_with
* ends_with
* contains

## Future Filter Support
* greater_than_or_equal_to
* less_than_or_equal_to
* on
* any

## Example Query Specification
```yaml
table: tasks
fields:
  created_at:
  assigned_to_member.name:
    label: "Assigned To"
    link: true
sort:
  - created_at: asc
  - edited_at: asc
  - description: desc
filter:
  not:
    assigned_to_member.name:
      contains: "Foo"
        starts_with: "Gary"
        ends_with: "Foster"
  charge.hours:
    greater_than: 1
    less_than: 8
  charge.actual_start_date:
    greater_than: 2016-05-01
  charge.actual_end_date:
    exactly: 2016-05-02 # Matches date and datetimes on specified day
  task_status:

# Missing grouping capabilities
aggregate:
  charges.hours:
    - sum
    - average
```

If you're using a polymorphic field, make sure use use the `poly|Model` syntax for associations.
