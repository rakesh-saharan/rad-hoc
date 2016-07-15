FactoryGirl.define do
  factory :album do
    title "Some Album"
    released_on Date.today
    performer
    association :owner, factory: :record
  end

  factory :track do
    title "Some Track"
    track_number 5
    album
  end

  factory :performer do
    title "Dr."
    name "Ron Paul"
  end

  factory :record do
    name "Great Music Inc."
  end
end
