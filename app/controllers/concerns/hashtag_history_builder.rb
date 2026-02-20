# frozen_string_literal: true

module HashtagHistoryBuilder
  def build_hashtag_history(hashtag)
    histories = hashtag.usage_histories
                       .where(date: 7.days.ago.to_date..Date.current)
                       .order(date: :desc)

    (0..6).map do |i|
      date = i.days.ago.to_date
      record = histories.find { |h| h.date == date }
      {
        day: date.to_time.to_i.to_s,
        uses: (record&.uses || 0).to_s,
        accounts: (record&.accounts || 0).to_s
      }
    end
  end
end
