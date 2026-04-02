# frozen_string_literal: true

namespace :home_feed do
  desc 'Backfill the home feed from existing data'
  task backfill: :environment do
    HomeFeedManager.backfill!
  end

  desc 'Clear and rebuild the home feed'
  task rebuild: :environment do
    HomeFeedEntry.delete_all
    HomeFeedManager.backfill!
  end

  desc 'Show home feed stats'
  task stats: :environment do
    puts "Home feed entries: #{HomeFeedEntry.count}"
  end
end
