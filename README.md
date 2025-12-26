# VanillaSky

A Ruby tool to selectively delete content from your Bluesky account.

## Features

- 🗑️ **Selective Deletion**: Choose what to delete - posts, replies, likes, reposts, or any combination
- ⏰ **Time-based**: Delete content older than a specified number of days (default: 90 days)
- 🎯 **ID-based**: Target specific posts by their IDs
- 🚫 **Exclude Lists**: Protect specific posts from deletion with exclude-ids
- 🔍 **Dry-run Mode**: Preview what would be deleted before committing (enabled by default)
- 🔐 **Secure**: Uses Bluesky app passwords for authentication
- 📊 **Detailed Output**: Progress tracking and comprehensive logging

## Prerequisites

- Ruby 3.0 or higher
- A Bluesky account
- A Bluesky app password (generate one at [bsky.app/settings/app-passwords](https://bsky.app/settings/app-passwords))

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

### Actually Delete Content

Add `--force` to perform actual deletions:
```bash
./vanillasky.rb posts --force
./vanillasky.rb posts replies likes --force
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
- **`likes`**: Posts you've liked
- **`reposts`**: Posts you've reposted/shared

You can specify multiple types in one command:
```bash
./vanillasky.rb posts replies likes reposts --force
```

## Authentication

### Environment Variables (Recommended)

Create a `.env` file:
```env
BLUESKY_HANDLE=your-handle.bsky.social
BLUESKY_APP_PASSWORD=your-app-password
```

### Interactive Prompts

If no environment variables are set, you'll be prompted for:
1. Your Bluesky handle (e.g., `username.bsky.social`)
2. Your app password (not your main account password!)

**Important**: Use an app password, not your main account password.

## Command Line Options

### Commands
- `posts` - Delete posts (not replies)
- `replies` - Delete replies to other posts
- `likes` - Delete likes
- `reposts` - Delete reposts

### Options
- `-d, --days DAYS` - Delete content older than DAYS (default: 90)
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

### Clean up likes older than 30 days
```bash
./vanillasky.rb likes --days 30 --force
```

## Safety Features

- 🔒 Secure authentication with app passwords
- 🛡️ **Dry-run mode by default** - requires `--force` to delete
- ⚠️ Confirmation prompt before actual deletion
- 🔍 Detailed preview of what will be deleted
- ⏱️ Rate limiting to avoid API issues
- 📋 Comprehensive logging
- 🚫 Exclude lists to protect important content
- ⛔ Mutual exclusion prevents conflicting options

## Example Output

```
🌌 VanillaSky - Bluesky Skeet Auto-Delete
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

1. **Authentication**: Connects to Bluesky using your handle and app password
2. **Command Parsing**: Determines what content types to process
3. **Scanning**: Fetches your content in batches, checking dates and types
4. **Filtering**: Applies time thresholds and exclude lists
5. **Preview/Execution**: Shows what would be deleted or performs deletions
6. **Rate Limiting**: Processes deletions with delays to respect API limits

## Version History

- **v0.2.1**: Fix SSL certificate CRL verification errors on Ruby 3.4+
- **v0.2**: Command-based interface, replies support, exclude-ids functionality
- **v0.1**: Original flag-based interface

## Security Notes

- Credentials are only used for the current session and never stored
- All API communications use HTTPS
- App passwords have limited scope compared to main passwords
- App passwords can be revoked anytime from Bluesky settings

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