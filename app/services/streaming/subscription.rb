# frozen_string_literal: true

module Streaming
  # 接続が購読しているストリーム1つ。ストリームの名前と必要な権限はMastodonと同じ
  class Subscription
    class Invalid < StandardError
      attr_reader :status

      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    # ストリームごとに、トークンにどれか1つあればよい権限
    STREAMS = {
      'user' => %w[read read:statuses],
      'user:notification' => %w[read read:notifications],
      'public' => %w[read read:statuses],
      'public:media' => %w[read read:statuses],
      'public:local' => %w[read read:statuses],
      'public:local:media' => %w[read read:statuses],
      'public:remote' => %w[read read:statuses],
      'public:remote:media' => %w[read read:statuses],
      'hashtag' => %w[read read:statuses],
      'hashtag:local' => %w[read read:statuses],
      'list' => %w[read read:lists],
      'direct' => %w[read read:statuses]
    }.freeze

    attr_reader :stream, :param

    # 購読の要求(streamと、ハッシュタグならtag、リストならlist)から作る。購読できなければInvalid
    def self.build(user, scopes, stream:, tag: nil, list: nil)
      stream = stream.to_s
      raise Invalid.new('Unknown stream type', 400) unless STREAMS.key?(stream)
      raise Invalid.new('Access token does not have the required scopes', 401) unless STREAMS[stream].intersect?(scopes)

      if stream.start_with?('hashtag')
        raise Invalid.new('Missing tag name parameter', 400) if tag.blank?

        return new(stream, tag.to_s)
      end

      if stream == 'list'
        raise Invalid.new('Not authorized to stream this list', 404) unless list.present? && user.lists.exists?(id: list)

        return new(stream, list.to_s)
      end

      new(stream, nil)
    end

    def initialize(stream, param)
      @stream = stream
      @param = param
    end

    # 配信するメッセージのstream欄。クライアントは購読したときの名前と値で自分宛てかを見分ける
    def name
      param ? [stream, param] : [stream]
    end

    def public_timeline?
      stream.start_with?('public')
    end

    def hashtag?
      stream.start_with?('hashtag')
    end

    def list?
      stream == 'list'
    end

    def timeline?
      public_timeline? || hashtag? || list?
    end

    def local_only?
      stream.include?(':local')
    end

    def remote_only?
      stream.include?(':remote')
    end

    def media_only?
      stream.end_with?(':media')
    end

    def ==(other)
      other.is_a?(Subscription) && other.stream == stream && other.param == param
    end
    alias eql? ==

    def hash
      [stream, param].hash
    end
  end
end
