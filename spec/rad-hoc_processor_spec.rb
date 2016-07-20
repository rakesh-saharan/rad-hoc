require 'spec_helper'

describe RadHoc::Processor do
  describe "#run" do
    context "raw queries" do
      it "can do a simple select query" do
        track = create(:track)
        processor = from_yaml('simple.yaml')
        validation = processor.validate
        expect(validation[:valid]).to be true

        result = processor.run_raw
        expect(result.length).to eq 1

        result_track = result.first
        expect(result_track['title']).to eq track.title
        expect(result_track['track_number']).to eq track.track_number
        expect(result_track['id']).to eq track.id
        expect(result_track['album_id']).to eq track.album_id
      end

      it "can handle simple associations" do
        track = create(:track)

        result = from_literal(
          <<-EOF
          table: tracks
          fields:
            album.title:
          EOF
        ).run_raw.first
        expect(result['title']).to eq track.album.title
      end

      it "can handle nested associations" do
        track = create(:track)

        result = from_literal(
          <<-EOF
          table: tracks
          fields:
            album.performer.title:
          EOF
        ).run_raw.first
        expect(result['title']).to eq track.album.performer.title
      end
    end

    context "interpreted queries" do
      it "can handle nested associations with columns that have identical names" do
        track = create(:track)

        result = from_literal(
          <<-EOF
          table: tracks
          fields:
            album.performer.title:
            album.title:
            title:
          EOF
        ).run[:data].first

        expect(result['title']).to eq track.title
        expect(result['album.title']).to eq track.album.title
        expect(result['album.performer.title']).to eq track.album.performer.title
      end

      it "can label fields automatically" do
        track = create(:track)

        labels = from_literal(
          <<-EOF
          table: tracks
          fields:
            title:
          EOF
        ).run[:labels]

        expect(labels['title']).to eq 'Title'
      end

      it "can label fields that are manually provided" do
        track = create(:track)

        labels = from_literal(
          <<-EOF
          table: tracks
          fields:
            title:
              label: "Name"
          EOF
        ).run[:labels]

        expect(labels['title']).to eq 'Name'
      end

      context "type casting" do
        it "can cast dates" do
          create(:album)

          result = from_literal(
            <<-EOF
            table: albums
            fields:
              released_on:
            EOF
          ).run[:data].first

          expect(result['released_on'].class).to be(Date)
        end
      end

      context "filtering" do
        it "can filter exact matches" do
          title = "My great album!"

          create(:track)
          create(:track, album: create(:album, title: title))

          results = from_literal(
            <<-EOF
            table: tracks
            fields:
              album.title:
            filter:
              album.title:
                exactly: "#{title}"
            EOF
          ).run[:data]

          expect(results.length).to eq 1
          expect(results.first['album.title']).to eq title
        end

        it "can filter numbers" do
          track_number = 3

          create(:track)
          create(:track, track_number: track_number)

          results = from_literal(
            <<-EOF
            table: tracks
            fields:
              track_number:
            filter:
              track_number:
                exactly: #{track_number}
            EOF
          ).run[:data]

          expect(results.length).to eq 1
          expect(results.first['track_number']).to eq track_number
        end
      end

      context "sorting" do
        it "can do simple sorts" do
          create(:track, title: "De Track")
          create(:track, title: "Albernon")

          results = from_literal(
            <<-EOF
            table: tracks
            fields:
              title:
            sort:
              - title: asc
            EOF
          ).run[:data]

          expect(results.first['title']).to be < results[1]['title']
        end

        it "can do sorts on associations" do
          t1 = create(:track, album: create(:album, title: "A Low One"))
          t2 = create(:track, album: create(:album, title: "The High One"))

          results = from_literal(
            <<-EOF
            table: tracks
            fields:
              id:
            sort:
              - album.title: desc
            EOF
          ).run[:data]

          expect(results.first['id']).to eq t2.id
          expect(results[1]['id']).to eq t1.id
        end

        it "can sort on multiple columns" do
          a = create(:album)
          t1 = create(:track, title: "Same", track_number: 4, album: a)
          t2 = create(:track, title: "Same", track_number: 3, album: a)
          t3 = create(:track, title: "Different", track_number: 9, album: a)

          results = from_literal(
            <<-EOF
            table: tracks
            fields:
              id:
            sort:
              - title: asc
              - track_number: asc
            EOF
          ).run[:data]

          r1, r2, r3 = results
          expect(r1['id']).to eq t3.id
          expect(r2['id']).to eq t2.id
          expect(r3['id']).to eq t1.id
        end
      end

      it "properly handles associations when we don't follow naming conventions" do
        album = create(:album)

        results = from_literal(
          <<-EOF
          table: albums
          fields:
            owner.name:
          EOF
        ).run[:data].first

        expect(results['owner.name']).to eq album.owner.name
      end
    end

    context "editing after initializing" do
      it "can add filters after initialization" do
        track = create(:track)

        results = from_literal(
          <<-EOF
          table: tracks
          fields:
            track_number:
          EOF
        ).add_filter('track_number', 'exactly', track.track_number - 1).run[:data]

        expect(results).to be_empty
      end

      it "can add filters on fields that are already filtered" do
        create(:track, track_number: 3)
        create(:track, track_number: 5)
        create(:track, track_number: 10)

        results = from_literal(
          <<-EOF
          table: tracks
          fields:
            track_number:
          filter:
            track_number:
              less_than: 8
          EOF
        ).add_filter('track_number', 'greater_than', 3).run[:data]

        expect(results.length).to eq 1
      end
    end

    context "validations" do
      it "validates that we've provided a table" do
        validation = from_literal(
          <<-EOF
          fields:
            title:
          EOF
        ).validate

        expect(validation[:errors].first[:name]).to eq :contains_table
      end

      it "validates that fields are of the correct data type" do
        validation = from_literal(
          <<-EOF
          table: tracks
          fields:
            title
            track_number
          EOF
        ).validate

        expect(validation[:valid]).to be false
      end
    end

    context "with scopes" do
      it "supports providing scopes" do
        create(:track)
        target = create(:track, title: 'Best Title')

        literal =
          <<-EOF
          table: tracks
          fields:
            id:
          EOF
        results = RadHoc::Processor.new(literal, scopes = [best_title: []]).run[:data]
        expect(results.length).to eq 1
        expect(results.first['id']).to eq target.id
      end

      it "supports providing scopes on an association" do
        create(:track)
        create(:track, album: create(:album, published: false))

        literal =
          <<-EOF
          table: tracks
          fields:
            album.published:
          EOF
        results = RadHoc::Processor.new(literal, scopes = [published: []]).run[:data]
        expect(results.length).to eq 1
      end

      it "supports providing scopes with an argument" do
        create(:track, album: create(:album, published: false))
        create(:track)

        literal =
          <<-EOF
          table: tracks
          fields:
            album.published:
          EOF
        scope = {is_published: [false]}
        results = RadHoc::Processor.new(literal, scopes = [scope]).run[:data]
        expect(results.length).to eq 1
      end
    end

    context "errors" do
      it "nicely when our associations are bad" do
        expect{from_literal(
          <<-EOF
          table: tracks
          fields:
            albuma.title:
          EOF
        ).run}.to raise_error(ArgumentError)
      end
    end
  end

  describe "#all_models" do
    it "returns all models used" do
      models = from_literal(
        <<-EOF
        table: tracks
        fields:
          id:
        sort:
          - album.owner.name: asc
        filter:
          album.performer.name:
            exactly: "Some guy"
        EOF
      ).all_models

      expect(models).to include(Track, Album, Record)
    end
  end

  describe "#all_cols" do
    it "returns all the columns used" do
      cols = from_literal(
        <<-EOF
        table: tracks
        fields:
          album.title:
          album.released_on:
        sort:
          - album.owner.name: asc
        EOF
      ).all_cols

      expect(cols).to include(
        Album.arel_table['title'],
        Album.arel_table['released_on'],
        Record.arel_table['name']
      )
    end
  end
end

