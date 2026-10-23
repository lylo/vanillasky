// VanillaSky — X (Twitter) browser console deleter
//
// The X API no longer offers a free way to list or bulk-delete your content,
// so this script drives the x.com web UI instead. It scrolls your profile
// timeline, finds your old posts / reposts / likes, and clicks the same
// buttons you would click by hand.
//
// HOW TO USE
//   1. Log in to x.com in Chrome, Firefox or Safari.
//   2. Open the tab you want to clean up:
//        https://x.com/<you>               -> posts (and your reposts)
//        https://x.com/<you>/with_replies  -> posts AND replies
//        https://x.com/<you>/likes         -> likes
//   3. Open the developer console (Cmd+Option+J / Ctrl+Shift+J).
//      Chrome asks you to type "allow pasting" the first time.
//   4. Edit CONFIG below, paste the whole file into the console, press Enter.
//   5. Watch the log. Call vanillasky.stop() to halt at any time.
//
// Dry run is the default. Set DRY_RUN: false to actually delete.
//
// Known limitations
//   - Dates for reposts and likes are the ORIGINAL post's date, not when you
//     reposted / liked it (the UI only shows the former).
//   - The UI cannot reliably distinguish a reply from a post, so "posts" means
//     "your own tweets on this tab". Use the Posts & replies tab to include
//     replies.
//   - Menu labels are matched by text, so set DELETE_LABEL if your X UI is not
//     in English.

(() => {
  const CONFIG = {
    DRY_RUN: true,          // false to really delete
    DAYS: 60,               // delete content older than this many days
    START_DATE: null,       // 'YYYY-MM-DD' — never delete anything before this date
    EXCLUDE_IDS: [],        // tweet IDs to keep, e.g. ['1234567890123456789']
    POSTS: true,            // delete your own tweets (and replies on the with_replies tab)
    REPOSTS: false,         // undo your reposts
    LIKES: true,            // unlike (only acts on the /likes tab)
    SKIP_PINNED: true,      // leave your pinned post alone
    SKIP_BOOKMARKED: true,  // leave anything you have bookmarked alone
    SKIP_LIKED: true,       // leave your own posts that you have liked alone
    MAX_ACTIONS: Infinity,  // stop after this many deletions
    DELAY_MS: 1500,         // pause between deletions
    SCROLL_IDLE_LIMIT: 8,   // consecutive scrolls with nothing new before giving up
    DELETE_LABEL: 'Delete', // text of the Delete menu item in your UI language
  };

  // ---------------------------------------------------------------------------

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const log = (...a) => console.log('%c🌌 VanillaSky', 'color:#8b5cf6;font-weight:bold', ...a);

  const stats = { posts: 0, reposts: 0, likes: 0, skipped: 0, failed: 0 };
  const seen = new Set();
  let running = true;

  if (window.vanillasky && window.vanillasky.running) {
    window.vanillasky.stop();
  }
  window.vanillasky = {
    stats,
    get running() { return running; },
    stop() { running = false; log('Stopping after the current item…'); },
  };

  // ---- Page context ----------------------------------------------------------

  const me = (document.querySelector('a[data-testid="AppTabBar_Profile_Link"]')?.getAttribute('href') || '')
    .replace(/^\//, '').toLowerCase();
  const path = location.pathname.replace(/\/+$/, '').toLowerCase();
  const [pathHandle, pathTab] = path.split('/').filter(Boolean);
  const onLikes = pathTab === 'likes';
  const onProfile = pathHandle === me && (!pathTab || pathTab === 'with_replies');

  // Anything posted on or before the cutoff day is fair game (same as the CLI).
  const cutoff = new Date();
  cutoff.setHours(23, 59, 59, 999);
  cutoff.setDate(cutoff.getDate() - CONFIG.DAYS);
  const startDate = CONFIG.START_DATE ? new Date(`${CONFIG.START_DATE}T00:00:00`) : null;
  const excluded = new Set(CONFIG.EXCLUDE_IDS.map(String));

  // ---- DOM helpers -----------------------------------------------------------

  async function waitFor(fn, timeout = 4000, interval = 100) {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      const v = fn();
      if (v) return v;
      await sleep(interval);
    }
    return null;
  }

  function pressEscape() {
    const target = document.activeElement || document.body;
    for (const type of ['keydown', 'keyup']) {
      target.dispatchEvent(new KeyboardEvent(type, { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
    }
  }

  // X sometimes replaces the timeline with "Something went wrong" + a Retry button.
  function clickRetry() {
    const btn = Array.from(document.querySelectorAll('[data-testid="primaryColumn"] button'))
      .find((b) => b.textContent.trim() === 'Retry');
    if (btn) { log('🔁 Clicking Retry'); btn.click(); }
  }

  function parseArticle(article) {
    const link = Array.from(article.querySelectorAll('a[href*="/status/"]')).find((a) => a.querySelector('time'));
    if (!link) return null;
    const m = link.getAttribute('href').match(/^\/([^/]+)\/status\/(\d+)/);
    if (!m) return null;

    const author = m[1].toLowerCase();
    const id = m[2];
    const date = new Date(link.querySelector('time').getAttribute('datetime'));
    const context = article.querySelector('[data-testid="socialContext"]')?.textContent || '';
    const isRepost = author !== me && !!article.querySelector('[data-testid="unretweet"]');
    const isPinned = author === me && /pinned/i.test(context);
    const isBookmarked = !!article.querySelector('[data-testid="removeBookmark"]');
    const isLiked = !!article.querySelector('[data-testid="unlike"]');
    const text = (article.querySelector('[data-testid="tweetText"]')?.innerText || '')
      .replace(/\s+/g, ' ').trim().slice(0, 60);

    let type = null;
    if (onLikes) type = article.querySelector('[data-testid="unlike"]') ? 'like' : null;
    else if (isRepost) type = 'repost';
    else if (author === me) type = 'post';

    return { article, id, author, date, text, type, isPinned, isBookmarked, isLiked };
  }

  // ---- Actions ---------------------------------------------------------------

  async function deleteOwnTweet({ article }) {
    const caret = article.querySelector('[data-testid="caret"]');
    if (!caret) return false;
    caret.click();

    const item = await waitFor(() =>
      Array.from(document.querySelectorAll('[role="menu"] [role="menuitem"]'))
        .find((el) => el.textContent.trim() === CONFIG.DELETE_LABEL));
    if (!item) { pressEscape(); return false; }
    item.click();

    const confirm = await waitFor(() => document.querySelector('[data-testid="confirmationSheetConfirm"]'));
    if (!confirm) { pressEscape(); return false; }
    confirm.click();

    return !!(await waitFor(() => !article.isConnected));
  }

  async function undoRepost({ article }) {
    const btn = article.querySelector('[data-testid="unretweet"]');
    if (!btn) return false;
    btn.click();

    const item = await waitFor(() => document.querySelector('[data-testid="unretweetConfirm"]'));
    if (!item) { pressEscape(); return false; }
    item.click();

    return !!(await waitFor(() => !article.isConnected || article.querySelector('[data-testid="retweet"]')));
  }

  async function unlike({ article }) {
    const btn = article.querySelector('[data-testid="unlike"]');
    if (!btn) return false;
    btn.click();
    return !!(await waitFor(() => !article.isConnected || article.querySelector('[data-testid="like"]')));
  }

  const ACTIONS = {
    post: { enabled: CONFIG.POSTS, run: deleteOwnTweet, stat: 'posts', label: 'post' },
    repost: { enabled: CONFIG.REPOSTS, run: undoRepost, stat: 'reposts', label: 'repost' },
    like: { enabled: CONFIG.LIKES, run: unlike, stat: 'likes', label: 'like' },
  };

  // ---- Main loop -------------------------------------------------------------

  function total() { return stats.posts + stats.reposts + stats.likes; }
  function fmt(d) { return d.toISOString().slice(0, 10); }

  async function process(item) {
    const { id, date, text, type, isPinned, isBookmarked, isLiked } = item;
    const action = ACTIONS[type];
    const prefix = `ID: ${id} | ${fmt(date)}${text ? ` - ${text}` : ''}`;

    if (!action || !action.enabled) return 'ignored';
    if (isPinned && CONFIG.SKIP_PINNED) { log(`📌 Skipping pinned ${prefix}`); stats.skipped++; return 'skipped'; }
    if (isBookmarked && CONFIG.SKIP_BOOKMARKED) { log(`🔖 Skipping bookmarked ${prefix}`); stats.skipped++; return 'skipped'; }
    if (isLiked && CONFIG.SKIP_LIKED && type === 'post') { log(`❤️ Skipping liked ${prefix}`); stats.skipped++; return 'skipped'; }
    if (excluded.has(id)) { log(`🚫 Excluded ${prefix}`); stats.skipped++; return 'skipped'; }
    if (date > cutoff) return 'too-new';
    if (startDate && date < startDate) return 'before-start';

    if (CONFIG.DRY_RUN) {
      log(`[DRY RUN] Would delete ${action.label} ${prefix}`);
      stats[action.stat]++;
      return 'done';
    }

    item.article.scrollIntoView({ block: 'center' });
    await sleep(200);
    const ok = await action.run(item);
    if (ok) {
      log(`🗑️ Deleted ${action.label} ${prefix}`);
      stats[action.stat]++;
    } else {
      log(`⚠️ Failed to delete ${action.label} ${prefix} — pausing 30s in case of rate limiting`);
      stats.failed++;
      await sleep(30000);
    }
    await sleep(CONFIG.DELAY_MS);
    return 'done';
  }

  async function run() {
    if (!me) { log('❌ Could not work out who you are — are you logged in?'); return; }
    if (!onLikes && !onProfile) {
      log(`❌ Open https://x.com/${me}, https://x.com/${me}/with_replies or https://x.com/${me}/likes first.`);
      return;
    }
    if (onLikes && !CONFIG.LIKES) { log('❌ On the likes tab but LIKES is false. Nothing to do.'); return; }

    log(`Logged in as @${me} on the ${onLikes ? 'likes' : pathTab === 'with_replies' ? 'posts & replies' : 'posts'} tab`);
    log(CONFIG.DRY_RUN ? '🔍 DRY RUN MODE - Nothing will be deleted' : '⚠️ LIVE MODE - content WILL be deleted');
    log(`🔍 Looking for content older than ${fmt(cutoff)}${startDate ? ` and on/after ${fmt(startDate)}` : ''}`);
    if (excluded.size) log(`🚫 Excluding ${excluded.size} IDs: ${[...excluded].join(', ')}`);

    let idle = 0;
    while (running && total() < CONFIG.MAX_ACTIONS) {
      const fresh = Array.from(document.querySelectorAll('article[data-testid="tweet"]'))
        .map(parseArticle)
        .filter((it) => it && !seen.has(it.id));

      if (fresh.length === 0) {
        clickRetry();
        if (++idle >= CONFIG.SCROLL_IDLE_LIMIT) break;
        window.scrollBy(0, window.innerHeight * 0.8);
        await sleep(1000);
        continue;
      }
      idle = 0;

      for (const item of fresh) {
        if (!running || total() >= CONFIG.MAX_ACTIONS) break;
        seen.add(item.id);
        const result = await process(item);
        // Profile timelines are reverse-chronological, so once an own post predates
        // START_DATE everything further down will too.
        if (result === 'before-start' && item.type === 'post' && !item.isPinned && !onLikes) {
          log(`📅 Reached ${fmt(startDate)} — stopping.`);
          running = false;
          break;
        }
      }

      const articles = document.querySelectorAll('article[data-testid="tweet"]');
      articles[articles.length - 1]?.scrollIntoView({ block: 'end' });
      window.scrollBy(0, 300);
      await sleep(800);
    }

    running = false;
    const verb = CONFIG.DRY_RUN ? 'Would have deleted' : 'Deleted';
    log(`✅ Finished. ${verb} ${stats.posts} posts, ${stats.reposts} reposts, ${stats.likes} likes. Skipped ${stats.skipped}, failed ${stats.failed}.`);
  }

  run().catch((e) => { running = false; console.error('🌌 VanillaSky crashed:', e); });
})();
