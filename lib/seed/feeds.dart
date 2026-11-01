/// Six bundled feeds across philosophy, history, psychology,
/// self-improvement, science and one tech feed. HTTPS only.
class SeedFeed {
  const SeedFeed(this.title, this.url, this.topic);
  final String title;
  final String url;
  final String topic;
}

const List<SeedFeed> kSeedFeeds = [
  SeedFeed('Daily Stoic — philosophy', 'https://dailystoic.com/feed/', 'Philosophy'),
  SeedFeed('History Extra — history', 'https://www.historyextra.com/latest-news/feed/', 'History'),
  SeedFeed('PsyPost — psychology', 'https://www.psypost.org/feed', 'Psychology'),
  SeedFeed('James Clear — self-improvement', 'https://jamesclear.com/feed', 'Self-improvement'),
  SeedFeed('Phys.org — science', 'https://phys.org/rss-feed/', 'Science'),
  SeedFeed('Ars Technica — tech', 'https://feeds.arstechnica.com/arstechnica/index', 'Tech'),
];
