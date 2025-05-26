# VanillaSky

A Ruby script to auto-delete posts from your Bluesky account.

## Features

- 🗑️ Automatically deletes posts older than a specified number of days (default: 90 days)
- 🔍 Default dry-run mode previews what would be deleted
- ⚡ Configurable timeframe
- 🔐 Secure authentication using Bluesky app passwords
- 📊 Progress tracking and detailed output

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

### Basic usage (dry run - shows what would be deleted)
```bash
./vanillasky.rb
```

### Actually delete posts (requires force flag for safety)
```bash
./vanillasky.rb --force
```

### Custom timeframe (e.g., delete posts older than 30 days)
```bash
./vanillasky.rb --days 30 --force
```

### Dry run (preview what would be deleted without actually deleting - the default)
```bash
./vanillasky.rb --dry-run
```

### Help
```bash
./vanillasky.rb --help
```

## Authentication

When you run the script, you'll be prompted for:
1. Your Bluesky handle (e.g., `username.bsky.social`)
2. Your app password (not your main account password!)

**Important**: Use an app password, not your main account password. You can create app passwords in your Bluesky settings.

## Safety Features

- 🔒 Uses app passwords for secure authentication
- 🛡️ **Dry-run mode by default** - you must use `--force` to actually delete
- ⚠️ Confirmation prompt before deletion (unless in dry-run mode)
- 🔍 Preview deletions before committing
- ⏱️ Rate limiting to avoid API issues
- 📋 Detailed logging of what's being deleted

## Example Output

```
🌌 VanillaSky - Bluesky Post Auto-Deletion Tool
=============================================
Enter your Bluesky handle (e.g., user.bsky.social): alice.bsky.social
Enter your app password:
✅ Successfully authenticated as alice.bsky.social
🔍 Scanning for posts older than 2024-02-25...
....
📋 Found 15 posts older than 90 days
⚠️  This will permanently delete these posts. Continue? (y/N) y
🗑️  Deleted (1/15): 2024-01-15 - Just tried that new coffee shop downtown...
🗑️  Deleted (2/15): 2024-01-10 - Beautiful sunset today! 📸
...
✅ Successfully deleted 15 out of 15 posts
```

**Note**: The above example shows output when using `--force`. Without the force flag, you'll see a dry-run preview instead.

## Command Line Options

- `-d, --days DAYS`: Delete posts older than DAYS (default: 90)
- `-n, --dry-run`: Show what would be deleted without actually deleting (default)
- `-f, --force`: Actually delete posts (required to disable dry-run mode)
- `-h, --help`: Show help message

## How It Works

1. **Authentication**: Connects to Bluesky using your handle and app password
2. **Scanning**: Fetches your posts in batches, checking creation dates
3. **Filtering**: Identifies posts older than the specified threshold
4. **Confirmation**: Asks for confirmation before deletion (unless dry-run)
5. **Deletion**: Removes old posts one by one with rate limiting

## Security Notes

- Your credentials are only used for the current session and are not stored
- The script uses HTTPS for all API communications
- App passwords have limited scope compared to your main password
- You can revoke app passwords at any time from your Bluesky settings

## Limitations

- Only deletes your own posts (not reposts or likes)
- Processes posts sequentially to respect rate limits
- Requires manual confirmation for each run (safety feature)

## Contributing

Feel free to open issues or submit pull requests if you find bugs or have suggestions for improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Disclaimer**: This tool permanently deletes your posts. Always test with `--dry-run` first and use at your own risk.
