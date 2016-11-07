require 'spec_helper'

describe RadHoc::Processor do
  describe "#run" do
    context "interpreted queries" do
      context "associations" do
        it "can handle nested associations with columns that have identical names" do
          track = create(:track)

          result = from_literal(
            <<-EOF
            table: tracks
            fields:
              album.performer.title:
                type: string
              album.title:
                type: string
              title:
                type: string
            filter: {}
            sort: []
            EOF
          ).run[:data].first

          expect(result['title']).to eq track.title
          expect(result['album.title']).to eq track.album.title
          expect(result['album.performer.title']).to eq track.album.performer.title
        end
      end

      context "labels" do
        it "can label fields automatically" do
          track = create(:track)

          labels = from_literal(
            <<-EOF
            table: tracks
            fields:
              title:
                type: string
            filter: {}
            sort: []
            EOF
          ).run[:labels]

          expect(labels['title']).to eq 'Title'
        end

        it "can label fields on associations" do
          track = create(:track)

          labels = from_literal(
              <<-EOF
            table: tracks
            fields:
              title:
                type: string
              album.performer.title:
                type: string
              album.title:
                type: string
            filter: {}
            sort: []
          EOF
          ).run[:labels]

          expect(labels['title']).to eq 'Title'
          expect(labels['album.title']).to eq 'Album Title'
          expect(labels['album.performer.title']).to eq 'Performer Title'
        end

        it "can label fields that are manually provided" do
          track = create(:track)

          labels = from_literal(
            <<-EOF
            table: tracks
            fields:
              title:
                type: string
                label: "Name"
            filter: {}
            sort: []
            EOF
          ).run[:labels]

          expect(labels['title']).to eq 'Name'
        end
      end

      context "type casting" do
        it "can cast dates" do
          create(:album)

          result = from_literal(
            <<-EOF
            table: albums
            fields:
              released_on:
                type: date
            filter: {}
            sort: []
            EOF
          ).run[:data].first

          expect(result['released_on'].class).to be(Date)
        end

        it "can cast times" do
          create(:performance)

          result = from_literal(
            <<-EOF
            table: performances
            fields:
              start_time:
                type: datetime
            filter: {}
            sort: []
            EOF
          ).run[:data].first

          expect(result['start_time'].class).to be(Time)
        end
      end

      context "linking" do
        it "always returns an id but doesn't add them to labels" do
          track = create(:track)

          result = from_literal(
            <<-EOF
            table: tracks
            fields:
              album.title:
                type: string
              title:
                type: string
            filter: {}
            sort: []
            EOF
          ).run
          data = result[:data].first
          labels = result[:labels]

          expect(data['album.id']).to eq track.album.id
          expect(data['id']).to eq track.id
          expect(data.keys.length).to eq 4
          expect(labels.length).to eq 2
        end

        it "provides information required for linking" do
          track = create(:track)

          result = from_literal(
            <<-EOF
            table: tracks
            fields:
              album.title:
                type: string
                link: true
            filter: {}
            sort: []
            EOF
          ).run

          expect(result[:linked].to_a).to include ['album.title', Album]
          expect(result[:data].first['album.id']).to eq track.id
        end
      end

      context "merge" do
        let(:title) { "My great album!" }
        let(:literal) {
            <<-EOF
            table: tracks
            fields:
              album.title:
                type: string
            filter:
              album.title:
                exactly: *title
            sort: []
            EOF
        }
        let(:merge) { {'title' => title} }

        before(:each) do
          create(:track)
          create(:track, album: create(:album, title: title))
        end

        it "can merge filters" do
          results = described_class.new(literal, rejected_tables, [], merge).run[:data]

          expect(results.length).to eq 1
          expect(results.first['album.title']).to eq title
        end

        it "can validate even though merge filters are not yet set" do
          processor = described_class.new(literal, rejected_tables)
          expect(processor.validate).to be_empty
          processor.merge = merge
          results = processor.run[:data]

          expect(results.length).to eq 1
          expect(results.first['album.title']).to eq title
        end
      end

      context "filtering" do
        context "basic filters" do
          it "can filter exact matches" do
            title = "My great album!"

            create(:track)
            create(:track, album: create(:album, title: title))

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                album.title:
                 type: string
              filter:
                album.title:
                  exactly: "#{title}"
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['album.title']).to eq title
          end

          it "doesn't blow up with unicode" do
            dansei = '男性'
            create(:track, title: '女性')
            create(:track, title: dansei)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                title:
                  type: string
              filter:
                title:
                  exactly: #{dansei}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['title']).to eq dansei
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
                  type: integer
              filter:
                track_number:
                  exactly: #{track_number}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['track_number']).to eq track_number
          end

          it "can filter between times" do
            create(:performance, start_time: 5.days.ago)
            correct = create(:performance, start_time: 1.day.ago)
            create(:performance, start_time: 3.hours.ago)

            results = from_literal(
              <<-EOF
              table: performances
              fields:
                id:
                  type: integer
              filter:
                start_time:
                  between:
                    - #{26.hours.ago.iso8601}
                    - #{4.hours.ago.iso8601}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['id']).to eq correct.id
          end

          it "can filter between dates" do
            create(:album, released_on: 5.months.ago.to_date)
            correct = create(:album, released_on: 3.months.ago.to_date)
            create(:album, released_on: Date.today)

            results = from_literal(
              <<-EOF
              table: albums
              fields:
                id:
                  type: integer
              filter:
                released_on:
                  between:
                    - #{4.months.ago.strftime('%F')}
                    - #{1.month.ago.strftime('%F')}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['id']).to eq correct.id
          end
        end

        context "match filters" do
          it "starts_with" do
            starter = 'Za'
            create(:track, title: "#{starter}Track")
            create(:track, title: "#{starter}Other Track")
            create(:track)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                id:
                  type: integer
              filter:
                title:
                  starts_with: "#{starter}"
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 2
          end

          it "ends_with" do
            ender = 'II'
            create(:track)
            create(:track, title: "Track #{ender}")
            create(:track, title: "Other Track #{ender}")

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                id:
                  type: integer
              filter:
                title:
                  ends_with: "#{ender}"
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 2
          end

          it "contains" do
            infix = 'Best'
            create(:track, title: "Track #{infix}")
            create(:track, title: "#Other #{infix} Track")
            create(:track, title: "#{infix} Track")
            create(:track)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                id:
                  type: integer
              filter:
                title:
                  contains: "#{infix}"
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 3
          end
        end

        context "any filters" do
          it "exactly_any" do
            title_1 = 'Test 1'
            title_2 = 'Test 2'
            create(:track, title: title_1)
            create(:track, title: 'Test 3')
            create(:track, title: title_2)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                title:
                  type: string
              filter:
                title:
                  exactly_any:
                    - #{title_1}
                    - #{title_2}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 2
            expect(results.map {|x| x['title']}).to eq [title_1, title_2]
          end
        end

        context "not filters" do
          it "can filter not_exactly" do
            title = 'Not this one'
            create(:track, title: 'This one')
            create(:track, title: title)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                title:
                  type: string
              filter:
                title:
                  not_exactly: #{title}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['title']).to_not eq title
          end

          it "can filter not between times" do
            create(:performance, start_time: 1.day.ago)
            correct = [
              create(:performance, start_time: 5.days.ago),
              create(:performance, start_time: 3.hours.ago)
            ]

            results = from_literal(
              <<-EOF
              table: performances
              fields:
                id:
                  type: integer
              filter:
                start_time:
                  not_between:
                    - #{26.hours.ago.iso8601}
                    - #{4.hours.ago.iso8601}
              sort: []
              EOF
            ).run[:data]

            expect(results.map {|x| x['id']}).to eq correct.map(&:id)
          end
        end

        context "block filters" do
          it "can filter not" do
            title = 'Not this one'
            create(:track, title: 'This one')
            create(:track, title: title)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                title:
                  type: string
              filter:
                not:
                  title:
                    exactly: #{title}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['title']).to_not eq title
          end

          it "can filter or" do
            track_1 = create(:track, title: 'Song', track_number: 1)
            track_2 = create(:track, title: 'Love and Music', track_number: 12)
            track_3 = create(:track, title: 'The Song of Life', track_number: 5)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                id:
                  type: integer
              filter:
                or:
                  title:
                    exactly: #{track_2.title}
                  track_number:
                    exactly: 5
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 2
            expect(results.first['id']).to eq track_2.id
            expect(results.last['id']).to eq track_3.id
          end

          it "can filter and" do
            track_1 = create(:track, title: 'Song', track_number: 1)
            track_2 = create(:track, title: 'Song', track_number: 12)
            track_3 = create(:track, title: 'The Song of Life', track_number: 12)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                id:
                  type: integer
              filter:
                or:
                  and:
                    title:
                      exactly: #{track_2.title}
                    track_number:
                      exactly: #{track_2.track_number}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 1
            expect(results.first['id']).to eq track_2.id
          end

          it "can filter not and" do
            track_1 = create(:track, title: 'Song', track_number: 1)
            track_2 = create(:track, title: 'Song', track_number: 12)
            track_3 = create(:track, title: 'The Song of Life', track_number: 12)

            results = from_literal(
              <<-EOF
              table: tracks
              fields:
                id:
                  type: integer
              filter:
                not:
                  title:
                    exactly: #{track_2.title}
                  track_number:
                    exactly: #{track_2.track_number}
              sort: []
              EOF
            ).run[:data]

            expect(results.length).to eq 2
            expect(results.first['id']).to eq track_1.id
            expect(results.last['id']).to eq track_3.id
          end
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
                type: string
            sort:
              - title: asc
            filter: {}
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
                type: integer
            sort:
              - album.title: desc
            filter: {}
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
                type: integer
            sort:
              - title: asc
              - track_number: asc
            filter: {}
            EOF
          ).run[:data]

          r1, r2, r3 = results
          expect(r1['id']).to eq t3.id
          expect(r2['id']).to eq t2.id
          expect(r3['id']).to eq t1.id
        end
      end

      context "polymorphics" do
        it "properly handles polymorphics" do
          album = create(:album)

          results = from_literal(
            <<-EOF
            table: albums
            fields:
              owner|Record.name:
                type: string
            filter: {}
            sort: []
            EOF
          ).run[:data].first

          expect(results['owner|Record.name']).to eq album.owner.name
        end

        it "can filter on a polymorphic" do
          record_1 = create(:record, name: "Record Company A")
          record_2 = create(:record, name: "Record Company B")
          album_1 = create(:album, owner: record_2)
          album_2 = create(:album, owner: record_1)

          results = from_literal(
            <<-EOF
            table: albums
            fields:
              id:
                type: integer
            filter:
              owner|Record.name:
                exactly: #{record_1.name}
            sort: []
            EOF
          ).run[:data]

          expect(results.length).to eq 1
          expect(results.first['id']).to eq album_2.id
        end
      end
    end

    context "validations" do
      it "validates that we've provided a table" do
        validation = from_literal(
          <<-EOF
          fields:
            title:
              type: string
          filter: {}
          sort: []
          EOF
        ).validate

        expect(validation.first[:name]).to eq :contains_table
      end

      it "validates that we've provided fields" do
        validation = from_literal(
          <<-EOF
          table: albums
          filter: {}
          sort: []
          EOF
        ).validate

        expect(validation.first[:name]).to eq :contains_fields
      end

      it "validates that we've provided filter" do
        validation = from_literal(
          <<-EOF
          table: albums
          fields:
            title:
              type: string
          sort: []
          EOF
        ).validate

        expect(validation.first[:name]).to eq :contains_filter
      end

      it "validates that we've provided sort" do
        validation = from_literal(
            <<-EOF
          table: albums
          fields:
            title:
              type: string
          filter: {}
        EOF
        ).validate

        expect(validation.first[:name]).to eq :contains_sort
      end

      it "validates that the fields have data types" do
        validation = from_literal(
          <<-EOF
          table: albums
          fields:
            id:
              type: integer
            title:
          filter: {}
          sort: []
          EOF
        ).validate

        expect(validation.first[:name]).to eq :has_data_type
      end

      it "validates that rejected tables are not included" do
        validation = from_literal(
            <<-EOF
          table: companies
          fields:
            id:
              type: integer
          filter: {}
          sort: []
        EOF
        ).validate

        expect(validation.first[:name]).to eq :valid_table
      end

      it "validates that associated rejected tables are not included" do
        validation = from_literal(
            <<-EOF
          table: members
          fields:
            id:
              type: integer
            security_group.name:
              type: string
          filter: {}
          sort: []
        EOF
        ).validate

        expect(validation.first[:message]).to eq "model SecurityGroup is not allowed"
      end

      it "validates that fields are of the correct data type" do
        validation = from_literal(
          <<-EOF
          table: tracks
          fields:
            title
            track_number
          filter: {}
          sort: []
          EOF
        ).validate

        expect(validation).to_not be_empty
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
              type: integer
          filter: {}
          sort: []
          EOF
        results = RadHoc::Processor.new(literal, rejected_tables, scopes = [best_title: []]).run[:data]
        expect(results.length).to eq 1
        expect(results.first['id']).to eq target.id
      end

      it "supports providing scopes on an association" do
        create(:track, published: true)
        create(:track, album: create(:album, published: false))

        literal =
          <<-EOF
          table: tracks
          fields:
            album.published:
              type: string
          filter: {}
          sort: []
          EOF
        results = RadHoc::Processor.new(literal, rejected_tables, scopes = [published: []]).run[:data]
        expect(results.length).to eq 1
      end

      it "supports providing scopes with an argument" do
        create(:track, album: create(:album, published: false), published: false)
        create(:track)

        literal =
          <<-EOF
          table: tracks
          fields:
            album.published:
              type: string
          filter: {}
          sort: []
          EOF
        scope = {is_published: [false]}
        results = RadHoc::Processor.new(literal, rejected_tables, scopes = [scope]).run[:data]
        expect(results.length).to eq 1
      end
    end

    context "limit and offset" do
      before(:each) do
        create(:track, title: "Yes!")
      end

      let!(:no) { create(:track, title: "No.") }
      let!(:yano) { create(:track, title: "Ya...No") }
      let(:query) {
        from_literal(
          <<-EOF
          table: tracks
          fields:
            title:
              type: string
            id:
              type: integer
          filter: {}
          sort: []
          EOF
        )
      }

      it "can limit queries" do
        results = query.run(limit: 1)[:data]
        expect(results.length).to eq 1
      end

      it "can offset queries" do
        results = query.run(offset: 2)[:data]
        expect(results.length).to eq 1
        expect(results.first['title']).to eq yano.title
      end

      it "can offset and limit queries" do
        create(:track)

        results = query.run(limit: 2, offset: 1)[:data]
        expect(results.length).to eq 2
        expect(results.first['title']).to eq no.title
        expect(results.last['id']).to eq yano.id
      end
    end

    context "errors" do
      it "nicely when our associations are bad" do
        expect{from_literal(
          <<-EOF
          table: tracks
          fields:
            albuma.title:
              type: string
          filter: {}
          sort: []
          EOF
        ).run}.to raise_error(ArgumentError)
      end

      it "doesn't run with invalid spec" do
        expect{from_literal(
            <<-EOF
          table: tracks
          fields:
            title:
          filter: {}
          sort: []
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
            type: integer
        sort:
          - album.owner|Record.name: asc
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
          - album.owner|Record.name: asc
        filter: {}
        EOF
      ).all_cols

      expect(cols).to include(
        Album.arel_table['title'],
        Album.arel_table['released_on'],
        Record.arel_table['name']
      )
    end
  end

  describe "#count" do
    it "returns the count" do
      create(:track)
      create(:track)
      create(:track)
      result = from_literal(
        <<-EOF
        table: tracks
        fields:
          id:
        filter: {}
        sort: []
        EOF
      )
      expect(result.count).to eq 3
    end
  end

  describe "#table_name" do
    it "returns the name of the table" do
      processor = from_literal(
        <<-EOF
        table: albums
        fields:
          id:
        filter: {}
        sort: []
        EOF
      )
      expect(processor.table_name).to eq 'albums'
    end
  end
end

