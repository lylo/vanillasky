# VanillaSky

A Ruby tool to selectively delete content from your Bluesky or Mastodon account.

## Features

- 🗑️ **Selective Deletion**: Choose what to delete - posts, replies, likes, reposts, or any combination
- 🌐 **Multi-platform**: Supports both Bluesky and Mastodon
- ⏰ **Time-based**: Delete content older than a specified number of days (default: 90 days)
- 🎯 **ID-based**: Target specific posts by their IDs
- 🚫 **Exclude Lists**: Protect specific posts from deletion with exclude-ids
- 🔍 **Dry-run Mode**: Preview what would be deleted before committing (enabled by default)
- 🔐 **Secure**: Uses app passwords (Bluesky) or access tokens (Mastodon) for authentication
- 📊 **Detailed Output**: Progress tracking and comprehensive logging

## Prerequisites

- Ruby 3.0 or higher
- A Bluesky and/or Mastodon account

## Installation

1. Clone or download this repository
2. Install dependencies:

   ```bash
   bundle install
   ```

3. Make the script executable:

   ```bash
   chmod +x vanillasky.rb
   ```

## Usage

VanillySky uses a command-based syntax where you specify what types of content to delete:

### Show Help and Version

```bash
./vanillasky.rb --help
./vanillasky.rb --version
```

### Basic Usage (Dry Run)

Delete posts older than 90 days (preview only):
```bash
./vanillasky.rb posts
```

Delete both posts and likes (preview only):
```bash
./vanillasky.rb posts likes
```

Delete only replies (preview only):
```bash
./vanillasky.rb replies
```

### Choosing a Platform

By default VanillaSky uses Bluesky. Use `--platform` / `-p` to switch to Mastodon:

```bash
./vanillasky.rb posts -p mastodon
./vanillasky.rb posts likes -p mastodon --days 30
```

### Actually Delete Content

Add `--force` to perform actual deletions:
```bash
./vanillasky.rb posts --force
./vanillasky.rb posts replies likes --force
./vanillasky.rb posts -p mastodon --force
```

### Custom Time Periods

Delete content older than 30 days:
```bash
./vanillasky.rb posts --days 30 --force
```

Delete everything (including today's content):
```bash
./vanillasky.rb posts likes reposts --days 0 --force
```

### Target Specific Posts

Delete only specific posts by their IDs:
```bash
./vanillasky.rb posts --ids abc123,def456,ghi789
```

### Exclude Specific Posts

Delete posts but protect certain ones:
```bash
./vanillasky.rb posts --exclude-ids important123,keepme456 --force
```

## Content Types

- **`posts`**: Top-level posts (not replies to other posts)
- **`replies`**: Your replies to other people's posts
- **`likes`**: Posts you've liked (Bluesky likes / Mastodon favourites)
- **`reposts`**: Posts you've reposted/shared (Bluesky reposts / Mastodon boosts)

You can specify multiple types in one command:
```bash
./vanillasky.rb posts replies likes reposts --force
```

## Authentication

### Bluesky

#### Environment Variables (Recommended)

Create a `.env` file:
```env
BLUESKY_HANDLE=your-handle.bsky.social
BLUESKY_APP_PASSWORD=your-app-password
```

Generate an app password at [bsky.app/settings/app-passwords](https://bsky.app/settings/app-passwords).

#### Interactive Prompts

If no environment variables are set, you'll be prompted for your handle and app password.

**Important**: Use an app password, not your main account password.

### Mastodon

#### Getting an Access Token

1. Log in to your Mastodon instance in a web browser
2. Go to **Preferences** → **Development** → **New application**
   (or visit `https://your-instance/settings/applications/new` directly)
3. Fill in the application name (e.g. "VanillaSky")
4. Under **Scopes**, select:
   - `read:statuses` — to fetch your posts, replies and boosts
   - `read:favourites` — to fetch your favourites
   - `write:statuses` — to delete posts, replies and boosts
   - `write:favourites` — to unfavourite posts
5. Click **Submit**
6. On the application page, copy **Your access token**

#### Environment Variables (Recommended)

Add to your `.env` file:
```env
MASTODON_INSTANCE=mastodon.social
MASTODON_ACCESS_TOKEN=your-access-token-here
```

#### Interactive Prompts

If no environment variables are set, you'll be prompted for your instance URL and access token.

## Command Line Options

### Commands
- `posts` - Delete posts (not replies)
- `replies` - Delete replies to other posts
- `likes` - Delete likes / favourites
- `reposts` - Delete reposts / boosts

### Options
- `-p, --platform PLATFORM` - Platform to use: `bluesky` (default) or `mastodon`
- `-d, --days DAYS` - Delete content older than DAYS (default: 90)
- `-s, --start-date DATE` - Don't delete anything before this date (YYYY-MM-DD)
- `-n, --dry-run` - Show what would be deleted without deleting (default)
- `-f, --force` - Actually delete content (required to disable dry-run)
- `--ids ID1,ID2,ID3` - Delete only specific IDs of the specified type
- `--exclude-ids ID1,ID2,ID3` - Exclude specific IDs from deletion
- `-h, --help` - Show help message
- `-v, --version` - Show version

## Example Workflows

### Clean up old posts but keep replies
```bash
# Preview
./vanillasky.rb posts --days 60

# Execute
./vanillasky.rb posts --days 60 --force
```

### Delete everything except specific important posts
```bash
./vanillasky.rb posts replies --exclude-ids important1,important2 --force
```

### Clean up Mastodon favourites older than 30 days
```bash
./vanillasky.rb likes -p mastodon --days 30 --force
```

### Delete old Mastodon boosts
```bash
./vanillasky.rb reposts -p mastodon --days 14 --force
```

## Safety Features

- 🔒 Secure authentication with app passwords / access tokens
- 🛡️ **Dry-run mode by default** - requires `--force` to delete
- ⚠️ Confirmation prompt before actual deletion
- 🔍 Detailed preview of what will be deleted
- ⏱️ Rate limiting to avoid API issues
- 📋 Comprehensive logging
- 🚫 Exclude lists to protect important content
- ⛔ Mutual exclusion prevents conflicting options

## Example Output

```
🌌 VanillaSky - Bluesky Auto-Delete
=========================================
✅ Successfully authenticated as alice.bsky.social
🔍 DRY RUN MODE - Nothing will be deleted
🚫 Excluding 2 IDs from deletion: important123, keepme456
🔍 Scanning for posts older than 2024-05-25...
....
📋 Found 23 posts older than 90 days
💬 Found 15 replies older than 90 days
[DRY RUN] ID: abc123 | 2024-03-15 - Just tried that new coffee shop...
[DRY RUN] ID: def456 | 2024-03-10 - Beautiful sunset today! 📸
...
🔍 DRY RUN: Would have deleted 23 posts
🔍 DRY RUN: Would have deleted 15 replies
```

## How It Works

1. **Platform Selection**: Picks Bluesky or Mastodon based on `--platform` flag
2. **Authentication**: Connects using your credentials
3. **Command Parsing**: Determines what content types to process
4. **Scanning**: Fetches your content in batches, checking dates and types
5. **Filtering**: Applies time thresholds and exclude lists
6. **Preview/Execution**: Shows what would be deleted or performs deletions
7. **Rate Limiting**: Processes deletions with delays to respect API limits

## Version History

- **v0.3.0**: Mastodon support, platform abstraction
- **v0.2.1**: Fix SSL certificate CRL verification errors on Ruby 3.4+
- **v0.2**: Command-based interface, replies support, exclude-ids functionality
- **v0.1**: Original flag-based interface

## Security Notes

- Credentials are only used for the current session and never stored
- All API communications use HTTPS
- Bluesky app passwords have limited scope and can be revoked anytime
- Mastodon access tokens can be revoked from your instance's Development settings

## Limitations

- Processes content sequentially to respect rate limits
- Cannot recover deleted content
- Some very old content might not be accessible via the API

## Contributing

Feel free to open issues or submit pull requests for bugs or feature suggestions.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**⚠️ Disclaimer**: This tool permanently deletes your content. Always test with dry-run mode first and use at your own risk.
