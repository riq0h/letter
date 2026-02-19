# frozen_string_literal: true

class Poll < ApplicationRecord
  belongs_to :object, class_name: 'ActivityPubObject', primary_key: :id
  has_many :poll_votes, dependent: :destroy
  has_many :voters, through: :poll_votes, source: :actor

  validates :expires_at, presence: true
  validates :options, presence: true
  validate :validate_options_format
  validate :validate_expiry_time, on: :create
  validate :validate_not_expired_on_create, on: :create

  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :active, -> { where(expires_at: Time.current..) }

  before_save :calculate_vote_counts

  def expired?
    expires_at < Time.current
  end

  def active?
    !expired?
  end

  def option_titles
    return [] unless options.is_a?(Array)

    options.filter_map { |option| option['title'] || option[:title] }
  end

  def option_votes_count(index)
    return 0 unless options.is_a?(Array) && index < options.length

    if remote_poll?
      options[index]['votes_count'] || 0
    else
      poll_votes.where(choice: index).count
    end
  end

  def remote_poll?
    object&.actor && !object.actor.local?
  end

  def vote_for!(actor, choices)
    return false if expired?

    choices = Array(choices)
    return false if choices.empty?
    return false if !multiple && choices.length > 1
    return false if choices.any? { |choice| choice.negative? || choice >= options.length }

    ActiveRecord::Base.transaction do
      # 既存の投票を削除（単一選択の場合、または複数選択で全て再投票する場合）
      poll_votes.where(actor: actor).destroy_all

      # 新しい投票を追加
      choices.each do |choice|
        poll_votes.create!(actor: actor, choice: choice)
      end

      calculate_vote_counts
      save!
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def voted_by?(actor)
    poll_votes.exists?(actor: actor)
  end

  def actor_choices(actor)
    poll_votes.where(actor: actor).pluck(:choice)
  end

  def to_mastodon_api
    {
      id: id.to_s,
      expires_at: expires_at.iso8601,
      expired: expired?,
      multiple: multiple,
      votes_count: total_votes_count,
      voters_count: total_voters_count,
      options: serialize_options,
      emojis: [],
      voted: false, # 現在のユーザに基づいてコントローラーで設定される
      own_votes: [] # 現在のユーザに基づいてコントローラーで設定される
    }
  end

  def total_votes_count
    if remote_poll?
      (options&.sum { |o| o['votes_count'] || 0 } || 0) + poll_votes.count
    else
      votes_count
    end
  end

  def total_voters_count
    if remote_poll?
      (voters_count || 0) + poll_votes.distinct.count(:actor_id)
    else
      multiple ? voters_count : votes_count
    end
  end

  private

  def validate_options_format
    return unless options

    unless options.is_a?(Array) && options.length.between?(2, 4)
      errors.add(:options, 'must be an array with 2-4 options')
      return
    end

    options.each_with_index do |option, index|
      errors.add(:options, "option #{index + 1} must have a title") unless option.is_a?(Hash) && option['title'].present?

      errors.add(:options, "option #{index + 1} title too long (maximum 50 characters)") if option['title'].to_s.length > 50
    end
  end

  def validate_expiry_time
    return unless expires_at
    return if remote_poll?

    min_expiry = 5.minutes.from_now - 10.seconds
    max_expiry = 1.month.from_now

    if expires_at < min_expiry
      errors.add(:expires_at, 'must be at least 5 minutes from now')
    elsif expires_at > max_expiry
      errors.add(:expires_at, 'cannot be more than 1 month from now')
    end
  end

  def validate_not_expired_on_create
    return unless expires_at && new_record?
    return if remote_poll?

    return unless expires_at <= Time.current

    errors.add(:expires_at, 'cannot be in the past')
  end

  def calculate_vote_counts
    return unless object&.actor&.local?

    self.votes_count = poll_votes.count
    self.voters_count = poll_votes.distinct.count(:actor_id)
  end

  def serialize_options
    return [] unless options.is_a?(Array)

    if remote_poll?
      local_vote_counts = poll_votes.group(:choice).count

      options.each_with_index.map do |option, index|
        {
          title: option['title'] || option[:title],
          votes_count: (option['votes_count'] || 0) + (local_vote_counts[index] || 0)
        }
      end
    else
      # 全投票データを一度に取得してN+1クエリを回避
      vote_counts_by_choice = poll_votes.group(:choice).count

      options.each_with_index.map do |option, index|
        {
          title: option['title'] || option[:title],
          votes_count: vote_counts_by_choice[index] || 0
        }
      end
    end
  end
end
