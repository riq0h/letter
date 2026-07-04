# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmoji do
  # image_presence等の他バリデーションと切り分けるため shortcode のエラーだけを見る
  def shortcode_errors(emoji)
    emoji.valid?
    emoji.errors[:shortcode]
  end

  describe 'shortcode length validation' do
    it 'accepts a long shortcode (>30 chars) for remote emoji' do
      long = 'plus50yende_tonjiruni_henkoudekimasu' # 35文字
      expect(shortcode_errors(build(:custom_emoji, :remote, shortcode: long))).to be_empty
    end

    it 'accepts a long shortcode for local too (unified limit, so remote copies never break)' do
      expect(shortcode_errors(build(:custom_emoji, :local, shortcode: 'a' * 40))).to be_empty
    end

    it 'rejects a shortcode longer than the max (100)' do
      expect(shortcode_errors(build(:custom_emoji, :remote, shortcode: 'a' * 101))).to be_present
    end

    it 'rejects a shortcode shorter than 2 chars' do
      expect(shortcode_errors(build(:custom_emoji, :remote, shortcode: 'a'))).to be_present
    end
  end
end
