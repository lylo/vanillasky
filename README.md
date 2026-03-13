# VanillaSky

A Ruby tool to selectively delete content from your Bluesky, Mastodon, or X (Twitter) account.

## Features

- 🗑️ **Selective Deletion**: Choose what to delete - posts, replies, likes, reposts, or any combination
- 🌐 **Multi-platform**: Supports Bluesky, Mastodon, and X (Twitter)
- ⏰ **Time-based**: Delete content older than a specified number of days (default: 90 days)
- 🎯 **ID-based**: Target specific posts by their IDs
- 🚫 **Exclude Lists**: Protect specific posts from deletion with exclude-ids
- 🔍 **Dry-run Mode**: Preview what would be deleted before committing (enabled by default)
- 📦 **Archive Support**: Import your X data archive to find and delete old tweets
- 🔐 **Secure**: Uses app passwords (Bluesky), access tokens (Mastodon), or OAuth 1.0a (X) for authentication
- 📊 **Detailed Output**: Progress tracking and comprehensive logging

## Prerequisites

- Ruby 3.0 or higher
- A Bluesky, Mastodon, and/or X account
- For X: a downloaded data archive (request at [x.com/settings/download_your_data](https://x.com/settings/download_your_data))

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

By default VanillaSky uses Bluesky. Use `--platform` / `-p` to switch:

```bash
./vanillasky.rb posts -p mastodon
./vanillasky.rb posts likes -p mastodon --days 30
./vanillasky.rb posts -p x --archive ~/path/to/x-archive
```

The X platform requires the `--archive` flag pointing to your extracted X data archive directory.

### Actually Delete Content

Add `--force` to perform actual deletions:
```bash
./vanillasky.rb posts --force
./vanillasky.rb posts replies likes --force
./vanillasky.rb posts -p mastodon --force
./vanillasky.rb posts likes -p x --archive ~/x-archive --force
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
- **`likes`**: Posts you've liked (Bluesky likes / Mastodon favourites / X likes)
- **`reposts`**: Posts you've reposted/shared (Bluesky reposts / Mastodon boosts / X retweets)

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

### X (Twitter)

X requires two things: **API credentials** for deleting content, and a **data archive** for finding your old content (since the X API no longer allows free listing of tweets).

#### Getting Your Data Archive

1. Go to [x.com/settings/download_your_data](https://x.com/settings/download_your_data)
2. Request your archive and wait for the email (can take 24+ hours)
3. Download and extract the ZIP file
4. Pass the extracted directory to VanillaSky with `--archive`

The archive should contain a `data/` directory with files like `tweets.js` and `like.js`.

#### Getting API Credentials

1. Go to the [X Developer Portal](https://developer.x.com/en/portal/dashboard)
2. Create a project and app (the free tier works for deletion)
3. On the app creation screen you'll see your **API Key**, **API Key Secret**, and **Bearer Token** — save the first two (Bearer Token is not needed)
4. Under **User authentication settings**, enable **OAuth 1.0a** with **Read and write** permissions
5. Go to your app's **Keys and tokens** tab
6. Under **Authentication Tokens**, click **Generate** to create your **Access Token and Secret** — save both

#### Environment Variables (Recommended)

Add to your `.env` file:
```env
X_API_KEY=your-api-key-here
X_API_KEY_SECRET=your-api-key-secret-here
X_ACCESS_TOKEN=your-access-token-here
X_ACCESS_TOKEN_SECRET=your-access-token-secret-here
```

#### Interactive Prompts

If no environment variables are set, you'll be prompted for all four credentials.

## Command Line Options

### Commands
- `posts` - Delete posts (not replies)
- `replies` - Delete replies to other posts
- `likes` - Delete likes / favourites
- `reposts` - Delete reposts / boosts

### Options
- `-p, --platform PLATFORM` - Platform to use: `bluesky` (default), `mastodon`, or `x`
- `-a, --archive PATH` - Path to extracted archive directory (required for X)
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

### Clean up old X tweets
```bash
# Preview
./vanillasky.rb posts -p x --archive ~/x-archive --days 60

# Execute
./vanillasky.rb posts -p x --archive ~/x-archive --days 60 --force
```

### Delete all X likes and retweets older than 90 days
```bash
./vanillasky.rb likes reposts -p x --archive ~/x-archive --force
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

1. **Platform Selection**: Picks Bluesky, Mastodon, or X based on `--platform` flag
2. **Authentication**: Connects using your credentials
3. **Command Parsing**: Determines what content types to process
4. **Scanning**: Fetches your content via API (Bluesky/Mastodon) or from your data archive (X)
5. **Filtering**: Applies time thresholds and exclude lists
6. **Preview/Execution**: Shows what would be deleted or performs deletions
7. **Rate Limiting**: Processes deletions with delays to respect API limits

## Version History

- **v0.4.0**: X (Twitter) support via data archive + API
- **v0.3.0**: Mastodon support, platform abstraction
- **v0.2.1**: Fix SSL certificate CRL verification errors on Ruby 3.4+
- **v0.2**: Command-based interface, replies support, exclude-ids functionality
- **v0.1**: Original flag-based interface

## Security Notes

- Credentials are only used for the current session and never stored
- All API communications use HTTPS
- Bluesky app passwords have limited scope and can be revoked anytime
- Mastodon access tokens can be revoked from your instance's Development settings
- X OAuth tokens can be revoked from the Developer Portal
- X data archives are read locally and never uploaded anywhere

## Limitations

- Processes content sequentially to respect rate limits
- Cannot recover deleted content
- Some very old content might not be accessible via the API
- X requires a data archive since the API no longer supports free listing of tweets
- X like dates are estimated from tweet IDs (snowflake timestamps), not the date you liked them
- X API free tier has strict rate limits (50 tweet deletions per 15 minutes)

## Contributing

Feel free to open issues or submit pull requests for bugs or feature suggestions.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**⚠️ Disclaimer**: This tool permanently deletes your content. Always test with dry-run mode first and use at your own risk.
