import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/db.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../repos/library.dart';
import '../repos/rss.dart' show ReadItem;
import '../repos/thought.dart';
import 'reader.dart';
import 'widgets.dart';

/// Full-screen vertical feed. One card = one thought (today's) or one short
/// read. Snapping PageView, opt-in auto-advance, right-side action rail.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

enum CardKind { thought, read }

class _FeedPageState extends State<FeedPage> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  List<(CardKind, ReadItem?)> _cards = [];
  String _thoughtOfTheDay = '';
  bool _loading = true;
  bool _pausedLongPress = false;
  bool _autoAdvance = false;
  Timer? _autoTimer;
  Map<String, int> _likeCounts = {};

  static const _thoughtHold = Duration(seconds: 12);
  static const _readHold = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final think = await ThoughtRepo.today();
    final reads = await LibraryRepo.fresh();
    _likeCounts = await _likeCountsFor(reads);
    if (!mounted) return;
    setState(() {
      _thoughtOfTheDay = think;
      _cards = [
        (CardKind.thought, null),
        ...[for (final r in reads) (CardKind.read, r)],
      ];
      _loading = false;
    });
    final v = await Db.kvGet('auto_advance');
    if (!mounted) return;
    setState(() => _autoAdvance = v == '1');
    _scheduleAutoAdvance();
  }

  Future<Map<String, int>> _likeCountsFor(List<ReadItem> reads) async {
    final out = <String, int>{};
    for (final r in reads.take(40)) {
      out[r.guid] = await LibraryRepo.likeCount(r.guid);
    }
    return out;
  }

  void _scheduleAutoAdvance() {
    _autoTimer?.cancel();
    if (!_autoAdvance || _pausedLongPress || !mounted || _cards.isEmpty) {
      return;
    }
    final i =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    if (i >= _cards.length) return;
    final hold = _cards[i].$1 == CardKind.thought ? _thoughtHold : _readHold;
    _autoTimer = Timer(hold, () {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == AppLifecycleState.resumed) _goTo(i + 1);
    });
  }

  Future<void> _goTo(int i) async {
    if (!_pageController.hasClients) return;
    if (i >= _cards.length) {
      await _load();
      return;
    }
    await _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    _scheduleAutoAdvance();
  }

  void _like() {
    HapticFeedback.mediumImpact();
    final i =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    if (i >= _cards.length) return;
    final read = _cards[i].$2;
    if (read == null) {
      LibraryRepo.recordInteraction('like', 'thought', 'thought:${Db.today()}')
          .then((_) => _load());
      return;
    }
    LibraryRepo.markLiked(read.id).then((_) => _load());
  }

  void _skip() {
    HapticFeedback.lightImpact();
    final i =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    if (i < _cards.length && _cards[i].$1 == CardKind.read) {
      final read = _cards[i].$2;
      if (read != null) LibraryRepo.markSkipped(read.id);
    }
    _goTo(i + 1);
  }

  void _save() {
    final i =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    if (i >= _cards.length || _cards[i].$1 == CardKind.thought) return;
    final read = _cards[i].$2;
    if (read == null) return;
    LibraryRepo.toggleSaved(read.id).then((_) => _load());
  }

  void _moreLikeThis() {
    final i =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    if (i >= _cards.length || _cards[i].$1 == CardKind.thought) return;
    final read = _cards[i].$2;
    if (read == null) return;
    LibraryRepo.moreLikeThis(read.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Noted. More like this soon.')));
    }
  }

  Future<void> _share() async {
    final i =
        _pageController.hasClients ? (_pageController.page?.round() ?? 0) : 0;
    if (i >= _cards.length) return;
    String text;
    final read = _cards[i].$2;
    if (_cards[i].$1 == CardKind.thought || read == null) {
      text = _thoughtOfTheDay;
    } else {
      text = '${read.title}\n\n${read.summary}';
    }
    await SharePlus.instance.share(ShareParams(text: text));
  }

  void _openReader(ReadItem read) {
    _autoTimer?.cancel();
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderPage(readId: read.id)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleAutoAdvance();
    } else {
      _autoTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: GCol.gold)),
      );
    }
    return Scaffold(
      backgroundColor: GCol.bg,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        physics: const PageScrollPhysics(),
        padEnds: false,
        itemCount: _cards.length,
        onPageChanged: (i) {
          HapticFeedback.selectionClick();
          _scheduleAutoAdvance();
        },
        itemBuilder: (context, i) {
          final card = _cards[i];
          return _PageEntrance(
            key: ValueKey('entrance-$i-${card.$2?.id}'),
            child: GestureDetector(
              onLongPressStart: (_) {
                _pausedLongPress = true;
                _autoTimer?.cancel();
                HapticFeedback.mediumImpact();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      duration: Duration(seconds: 2),
                      content: Text('Auto-advance paused')));
                }
              },
              onLongPressEnd: (_) {
                _pausedLongPress = false;
                _scheduleAutoAdvance();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(child: GoldGlow(intense: true)),
                  const Positioned.fill(child: GrainOverlay()),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: GestureDetector(
                      onTap: card.$1 == CardKind.read && card.$2 != null
                          ? () => _openReader(card.$2!)
                          : null,
                      child: card.$1 == CardKind.thought
                          ? ThoughtCard(text: _thoughtOfTheDay)
                          : (card.$2 != null
                              ? ReadCard(
                                  item: card.$2!,
                                  onOpen: () => _openReader(card.$2!))
                              : const SizedBox.shrink()),
                    ),
                  ),
                  _ActionRail(
                    likeCount: card.$1 == CardKind.thought
                        ? _likeCounts[Db.today()] ?? 0
                        : (card.$2 != null ? _likeCounts[card.$2!.guid] ?? 0 : 0),
                    onLike: _like,
                    onSkip: _skip,
                    onMoreLikeThis: _moreLikeThis,
                    onSave: _save,
                    onShare: () => _share(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The thought card: staggered serif headline + source tag.
class ThoughtCard extends StatefulWidget {
  const ThoughtCard({super.key, required this.text});

  final String text;

  @override
  State<ThoughtCard> createState() => _ThoughtCardState();
}

class _ThoughtCardState extends State<ThoughtCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          WordStagger(
            text: widget.text,
            controller: _c,
            style: const TextStyle(
              fontFamily: 'Playfair Display',
              fontSize: 34,
              height: 1.2,
              color: GCol.text,
              fontVariations: [FontVariation('wght', 600)],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Thought of the day',
              style: TextStyle(fontSize: 16, color: GCol.muted)),
          const SizedBox(height: 10),
          const SourceTag(label: 'growth • daily'),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

/// Read card: headline, 2-line hook, source tag. Tap opens the reader (hero).
class ReadCard extends StatelessWidget {
  const ReadCard({super.key, required this.item, required this.onOpen});

  final ReadItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sentenceStarts = item.summary.split(RegExp(r'(?<=[.!?]) '));
    StringBuffer buf = StringBuffer();
    for (final s in sentenceStarts.take(2)) {
      buf.write(' $s');
    }
    final hook = buf.toString().trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Hero(
            tag: 'read-${item.id}',
            child: Material(
              type: MaterialType.transparency,
              child: Text(
                item.title,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Playfair Display',
                  fontSize: 30,
                  height: 1.18,
                  color: GCol.text,
                  fontVariations: [FontVariation('wght', 600)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hook,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, height: 1.5, color: GCol.muted),
          ),
          const SizedBox(height: 12),
          Text('${item.estimatedMinutes()} min read',
              style: const TextStyle(fontSize: 16, color: GCol.gold)),
          const SizedBox(height: 10),
          SourceTag(label: item.topic),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

/// The right rail: Like (count), Skip, More like this, Save, Share.
class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.likeCount,
    required this.onLike,
    required this.onSkip,
    required this.onMoreLikeThis,
    required this.onSave,
    required this.onShare,
  });

  final int likeCount;
  final VoidCallback onLike;
  final VoidCallback onSkip;
  final VoidCallback onMoreLikeThis;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HeartBurst(
              onLiked: onLike,
              child: RailButton(
                  icon: Icons.favorite, label: 'Like', onTap: onLike, count: likeCount),
            ),
            RailButton(icon: Icons.close, label: 'Skip', onTap: onSkip),
            RailButton(
                icon: Icons.replay, label: 'More\nthis', onTap: onMoreLikeThis),
            RailButton(icon: Icons.bookmark_border, label: 'Save', onTap: onSave),
            RailButton(icon: Icons.share, label: 'Share', onTap: onShare),
          ],
        ),
      ),
    );
  }
}

/// Card entrance: fade + rise 16px over 350ms (degrades to a fade when the
/// system reduce-motion setting is on).
class _PageEntrance extends StatefulWidget {  const _PageEntrance({required this.child, super.key});

  final Widget child;

  @override
  State<_PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<_PageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Motion.entrance(context, _c, widget.child);
  }
}
