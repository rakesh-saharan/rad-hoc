# Rad hoc
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
If the spec is valid, `#validate` will return `{valid: true, errors: []}`. Otherwise, it will return `{valid: false, errors: [...]}` where the errors Array contains information about why the spec is invalid.

To run the query, use the `#run` method:
```ruby
results = processor.run
```
This returns a hash:
- `results[:data]`: an Array of Hashes with the selected values indexed by field key 
  - `[{"name" => "Some Company"}]` if there was one company with the name "Some Company" in the DB
- `results[:labels]`: a labels Hash for the field keys
  - `{'name' => 'Name'}` in this case

It will error if the specification is not valid, so check with `#validate` before using `#run` (once it's implemented).

## Modification Methods
Sometimes you just want to make a few changes to the query before running it. These methods provide a way to do that. All of these methods return `self`.

### `#add_filter`
| Argument  | Type   | Description                                  |
| --------- | ------ | -------------------------------------------  |
| key       | String | 'company.owner.name' style column specifier  |
| operation | String | comparison operator (same as YAML operators) |
| value     | Any    | value to compare against                     |

Adds a new filter to the query

## Example Query Specification
```yaml
table: tasks
fields:
  created_at:
  assigned_to_member.name:
    label: "Assigned To"
sort:
  - created_at: asc
  - edited_at: asc
  - description: desc
filter:
  - assigned_to_member.name:
      contains: " "
      not:
        starts_with: "Gary"
        ends_with: "Foster"
  - charges.hours:
      greater_than: 1
      less_than: 8
  - charges.actual_start_date:
      greater_than: 2016-05-01
  - charges.actual_end_date:
      on: 2016-05-02 # Matches date and datetimes on specified day
      greater_than_or_equal_to: 2016-05-02 12:00:00 -5
      less_than_or_equal_to: 2016-05-03 23:59:59 -5
  - task_status:
    any: # Translates to SQL IN
      - "Completed"
      - "Discarded"
# Missing grouping capabilities
aggregate:
  charges.hours:
    - sum
    - average
```
