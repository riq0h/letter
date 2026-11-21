# frozen_string_literal: true

FactoryBot.define do
  factory :custom_emoji do
    # Faker::Lorem.wordは単語が重複して一意性(uniqueness scope: domain)に落ちることがあるため、
    # 決定的なsequenceで生成する
    sequence(:shortcode) { |n| "emoji#{n}" }
    visible_in_picker { true }
    disabled { false }

    trait :local do
      domain { nil }

      after(:create) do |emoji|
        # ローカル絵文字の場合はActiveStorageのimageを添付（テスト用のダミー）
        emoji.image.attach(
          io: StringIO.new('dummy_image_data'),
          filename: 'test_emoji.png',
          content_type: 'image/png'
        )
      end
    end

    trait :remote do
      domain { 'example.com' }
      image_url { "https://example.com/emoji/#{shortcode}.png" }
    end

    trait :disabled do
      disabled { true }
    end

    trait :hidden do
      visible_in_picker { false }
    end

    # 具体的なshortcodeを指定する場合
    trait :smile do
      shortcode { 'smile' }
    end

    trait :heart do
      shortcode { 'heart' }
    end
  end
end
