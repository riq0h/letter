# frozen_string_literal: true

module ApplicationHelper
  include StatusSerializer

  def background_color
    stored_config = load_instance_config
    stored_config['background_color'] || '#fdfbfb'
  end

  def embed_code(post)
    embed_url = embed_post_url(username: post.actor.username, id: post.id)
    post_url = post_html_url(username: post.actor.username, id: post.id)
    script_url = "#{root_url}embed.js"

    <<~HTML.strip
      <div class="letter-embed" data-embed-url="#{embed_url}">
        <a href="#{post_url}">@#{post.actor.username}の投稿を見る</a>
      </div>
      <script async src="#{script_url}"></script>
    HTML
  end

  private

  def load_instance_config
    InstanceConfig.all_as_hash
  rescue StandardError => e
    Rails.logger.error "Failed to load config from database: #{e.message}"
    {}
  end
end
