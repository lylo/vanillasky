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

The X API free tier cannot delete likes and has tight rate limits, so there is also `x_console.js`: a standalone browser script the user pastes into the x.com developer console. It does not use the Ruby platform interface. It scrolls the profile / with_replies / reposts / likes tab, re-scanning the DOM before each item (X re-renders timeline cells after every deletion, so article references go stale), parses each `article[data-testid="tweet"]` (status link + `time[datetime]` for ID and date, `socialContext` + `unretweet` button for reposts), and clicks the UI controls (`caret` → "Delete" menu item → `confirmationSheetConfirm`; `unretweet` → `unretweetConfirm`; `unlike`). Config lives in the `CONFIG` object at the top of the file; dry run is the default. Reference markup for the selectors was taken from a saved x.com page; there is no automated test for it in the repo.

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
