# Mastodon API Implementation Status

## Currently Implemented ✅

### Accounts
- `GET /api/v1/accounts/verify_credentials` ✅
- `PATCH /api/v1/accounts/update_credentials` ✅
- `GET /api/v1/accounts/relationships` ✅
- `GET /api/v1/accounts/:id` ✅
- `GET /api/v1/accounts/:id/statuses` ✅
- `GET /api/v1/accounts/:id/followers` ✅
- `GET /api/v1/accounts/:id/following` ✅
- `POST /api/v1/accounts/:id/follow` ✅
- `POST /api/v1/accounts/:id/unfollow` ✅
- `POST /api/v1/accounts/:id/block` ✅
- `POST /api/v1/accounts/:id/unblock` ✅
- `POST /api/v1/accounts/:id/mute` ✅
- `POST /api/v1/accounts/:id/unmute` ✅

### Statuses
- `GET /api/v1/statuses/:id` ✅
- `GET /api/v1/statuses/:id/context` ✅
- `POST /api/v1/statuses` ✅
- `DELETE /api/v1/statuses/:id` ✅
- `PUT /api/v1/statuses/:id` ✅
- `POST /api/v1/statuses/:id/favourite` ✅
- `POST /api/v1/statuses/:id/unfavourite` ✅
- `POST /api/v1/statuses/:id/reblog` ✅
- `POST /api/v1/statuses/:id/unreblog` ✅

### Media
- `POST /api/v1/media` ✅
- `POST /api/v2/media` ✅
- `GET /api/v1/media/:id` ✅
- `PUT /api/v1/media/:id` ✅

### Timelines
- `GET /api/v1/timelines/home` ✅
- `GET /api/v1/timelines/public` ✅

### Apps & OAuth
- `POST /api/v1/apps` ✅
- `GET /api/v1/apps/verify_credentials` ✅

### Instance
- `GET /api/v1/instance` ✅ (deprecated)
- `GET /api/v2/instance` ✅

### Search
- `GET /api/v2/search` ✅ (basic)

### Bookmarks
- `POST /api/v1/statuses/:id/bookmark` ✅
- `POST /api/v1/statuses/:id/unbookmark` ✅
- `GET /api/v1/bookmarks` ✅

### Favourites
- `GET /api/v1/favourites` ✅

### Notifications (Enhanced)
- `GET /api/v1/notifications` ✅
- `GET /api/v1/notifications/:id` ✅
- `POST /api/v1/notifications/:id/dismiss` ✅
- `POST /api/v1/notifications/clear` ✅

### Search (Enhanced)
- `GET /api/v1/accounts/search` ✅
- `GET /api/v1/accounts/lookup` ✅

### Other
- `GET /api/v1/custom_emojis` ✅
- `GET /api/v1/markers` ✅
- `POST /api/v1/markers` ✅

## High Priority Missing ⚠️

### Account Features
- `GET /api/v1/accounts/:id/featured_tags` ✅
- `GET /api/v1/featured_tags` ✅
- `POST /api/v1/featured_tags` ✅
- `DELETE /api/v1/featured_tags/:id` ✅
- `GET /api/v1/featured_tags/suggestions` ✅

## Medium Priority Missing 📋

### Status Features
- `POST /api/v1/statuses/:id/pin` ✅
- `POST /api/v1/statuses/:id/unpin` ✅
- `GET /api/v1/statuses/:id/reblogged_by` ✅
- `GET /api/v1/statuses/:id/favourited_by` ✅

### Conversations
- `GET /api/v1/conversations` ✅
- `GET /api/v1/conversations/:id` ✅
- `DELETE /api/v1/conversations/:id` ✅
- `POST /api/v1/conversations/:id/read` ✅

### Lists
- `GET /api/v1/lists` ✅
- `POST /api/v1/lists` ✅
- `GET /api/v1/lists/:id` ✅
- `PUT /api/v1/lists/:id` ✅
- `DELETE /api/v1/lists/:id` ✅
- `GET /api/v1/lists/:id/accounts` ✅
- `POST /api/v1/lists/:id/accounts` ✅
- `DELETE /api/v1/lists/:id/accounts` ✅

### Filters
- `GET /api/v1/filters` ✅
- `POST /api/v1/filters` ✅
- `GET /api/v1/filters/:id` ✅
- `PUT /api/v1/filters/:id` ✅
- `DELETE /api/v1/filters/:id` ✅

## Low Priority Missing 📝

### Follow Requests
- `GET /api/v1/follow_requests` ✅
- `POST /api/v1/follow_requests/:id/authorize` ✅
- `POST /api/v1/follow_requests/:id/reject` ✅

### Domain Blocks
- `GET /api/v1/domain_blocks` ✅
- `POST /api/v1/domain_blocks` ✅
- `DELETE /api/v1/domain_blocks` ✅

### Suggestions
- `GET /api/v1/suggestions` ✅
- `DELETE /api/v1/suggestions/:id` ✅

### Trends
- `GET /api/v1/trends/tags` ✅
- `GET /api/v1/trends/statuses` ✅
- `GET /api/v1/trends/links` ✅

### Admin APIs
- `GET /api/v1/admin/dashboard` ✅ (サーバ統計情報)
- `GET /api/v1/admin/accounts` ✅ (アカウント管理)
- `GET /api/v1/admin/accounts/:id` ✅
- `POST /api/v1/admin/accounts/:id/suspend` ✅
- `POST /api/v1/admin/accounts/:id/enable` ✅
- `DELETE /api/v1/admin/accounts/:id` ✅
- `GET /api/v1/admin/reports` ✅ (レポート機能は簡素化)

### Push Notifications
- `GET /api/v1/push/subscription` ✅
- `POST /api/v1/push/subscription` ✅
- `PUT /api/v1/push/subscription` ✅
- `DELETE /api/v1/push/subscription` ✅

## Not Applicable for Letter 🚫

### Features not planned for Letter's 2-user design:
- Reports (`/api/v1/reports/*`)
- Endorsements (`/api/v1/endorsements`)
- Followed tags (`/api/v1/followed_tags`) ✅ (stub - returns empty)
- Announcements (`/api/v1/announcements`) ✅ (stub - returns empty)
- Preferences (`/api/v1/preferences`) ✅ (stub - returns defaults)

## Implementation Priority Order

1. **Bookmarks** (High usage in clients)
2. **Notifications** (Core functionality)
3. **Favourites list** (User content management)
4. **Enhanced Search** (Account lookup)
5. **Status interactions** (reblogged_by, favourited_by)
6. **Conversations** (DM functionality)
7. **Lists** (Content organization)
8. **Filters** (Content curation)