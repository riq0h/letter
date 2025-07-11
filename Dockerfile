ARG RUBY_VERSION=3.4.1
FROM ruby:$RUBY_VERSION-slim AS base

# 基本的なシステム依存関係をインストール
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    jq \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

# ビルドステージ
FROM base AS builder

# ビルド依存関係をインストール
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libsqlite3-dev \
    nodejs \
    npm \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# ワーキングディレクトリを設定
WORKDIR /app

# 依存関係ファイルをコピー
COPY --link Gemfile Gemfile.lock ./
COPY --link package*.json ./

# Bundlerの設定
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/cache

# Node.js依存関係をインストール
RUN npm ci --production && \
    npm cache clean --force

# アプリケーションコードをコピー
COPY --link . .

# アセットをプリコンパイル
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# 実行ステージ
FROM base AS runner

# procpsを追加（ヘルスチェック用）
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y procps && \
    rm -rf /var/lib/apt/lists/*

# ワーキングディレクトリを設定
WORKDIR /app

# セキュリティのため非rootユーザを作成
RUN groupadd --system --gid 1000 letter && \
    useradd letter --uid 1000 --gid 1000 --create-home --shell /bin/bash

# ビルドステージから必要なファイルをコピー
COPY --from=builder --chown=letter:letter /app /app
COPY --from=builder --chown=letter:letter /usr/local/bundle /usr/local/bundle

# 必要なディレクトリを作成
RUN mkdir -p \
    tmp/pids \
    tmp/cache \
    log \
    storage \
    public/uploads \
    && chown -R letter:letter /app

# エントリーポイントスクリプトをコピー
COPY --chown=letter:letter docker/entrypoint.sh /usr/bin/entrypoint.sh
RUN chmod +x /usr/bin/entrypoint.sh

USER letter

# ポートを公開
EXPOSE 3000

# エントリーポイントを設定
ENTRYPOINT ["entrypoint.sh"]

# デフォルトコマンド
CMD ["rails", "server", "-b", "0.0.0.0"]
