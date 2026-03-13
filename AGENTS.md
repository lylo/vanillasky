# AGENTS.md

## Project Overview

VanillaSky is a Ruby CLI tool for selectively deleting old content (posts, replies, likes, reposts) from social media accounts. It supports Bluesky, Mastodon, and X (Twitter).

## Architecture

Each platform is a separate class in its own file, implementing a common interface:

- `bluesky_platform.rb` — Bluesky via AT Protocol API
- `mastodon_platform.rb` — Mastodon via REST API
- `x_platform.rb` — X (Twitter) via data archive + OAuth 1.0a API v2

`vanillasky.rb` is the main entry point: it parses CLI args, creates the appropriate platform, and orchestrates the fetch/filter/delete flow.

### Platform Interface

Every platform class must implement:

- `platform_name` — display name string
- `authenticate` — verify credentials and set up session state
- `fetch_old_posts(cutoff_date, start_date, exclude_ids)` — returns array of post hashes
- `fetch_old_replies(cutoff_date, start_date, exclude_ids)` — returns array of reply hashes
- `fetch_old_likes(cutoff_date, start_date, exclude_ids)` — returns array of like hashes
- `fetch_old_reposts(cutoff_date, start_date, exclude_ids)` — returns array of repost hashes
- `fetch_record_by_id(id, collection)` — fetch a single item by ID
- `collection_for_type(type)` — map `:post`, `:reply`, `:repost`, `:like` to platform-specific collection names
- `delete_post(uri)`, `delete_like(uri)`, `delete_repost(uri)` — delete a single item, return boolean
- `delete_delay` — seconds to sleep between deletions
- `item_id(item)` — extract display ID from an item hash

Item hashes use the keys `:uri`, `:created_at`, `:text` (optional), and `:reply` (optional).

### X Platform Specifics

Unlike Bluesky and Mastodon, X does not offer a free API to list tweets. Instead, `XPlatform` reads the user's downloaded data archive (`data/tweets.js`, `data/like.js`) to find content, and uses the X API v2 with OAuth 1.0a to perform deletions.

Likes in the archive don't have timestamps, so dates are derived from Twitter snowflake IDs.

## Running Tests

```bash
ruby test/vanillasky.rb
```

Tests use Minitest. The X platform archive tests create temporary directories with mock archive data.

## Environment Variables

See `.env.example` for all supported variables. Never commit `.env`.

## Conventions

- No external HTTP client gems — uses `net/http` from stdlib
- All platforms share the same `create_http` pattern with SSL and certificate store configuration
- Dry-run mode is the default; `--force` is required for actual deletion
- Rate limit handling: platforms implement retry logic for 429 responses
