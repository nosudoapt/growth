import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../repos/library.dart';
import '../repos/rss.dart';
import 'widgets.dart';

/// Clean reader: dark, adjustable font size, estimated read time, live
/// actually-spent time bookkeeping (pauses when backgrounded), plus the
/// after-read actions and one optional note.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.readId});

  final int readId;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver {
  ReadItem? _item;
  double _fontScale = 1.0; // 0.85 .. 1.35
  Stopwatch _watch = Stopwatch();
  Timer? _saveTimer;
  double _minutesThisSession = 0.0;
  bool _openedNoteField = false;
  final _noteController = TextEditingController();

  double get countedMinutes {
    // Every completed 30s chunk is credited instantly, remainder on close.
    return _minutesThisSession + _watch.elapsedMilliseconds / 60000.0;
  }

  String get displayMinutes =>
      (countedMinutes + 0.4).floor() <= 0 ? '<1' : countedMinutes.round().toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final item = await LibraryRepo.byId(widget.readId);
    if (!mounted) return;
    setState(() {
      _item = item;
      if (item != null) {
        _noteController.text = item.note;
      }
    });
    if (item != null) {
      await LibraryRepo.markOpened(item.id);
      _watch.start();
      // Save actual time every 30 seconds.
      _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _flushTime();
      });
    }
  }

  Future<void> _flushTime() async {
    final mins = _watch.elapsedMilliseconds / 60000.0;
    _watch.reset();
    if (mins <= 0.05) return; // ignore under-3s blips
    final item = _item;
    if (item == null) return;
    _minutesThisSession += mins;
    await LibraryRepo.addReadingTime(item.id, mins);
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reading time pauses whenever the app is backgrounded.
    if (state == AppLifecycleState.resumed) {
      _watch.start();
    } else {
      _watch.stop();
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        _flushTime();
      }
    }
  }

  Future<void> _setLike(bool like) async {
    final item = _item;
    if (item == null) return;
    if (like) {
      await LibraryRepo.markLiked(item.id);
    } else {
      await LibraryRepo.unmarkLiked(item.id);
    }
    await _reloadItem();
  }

  Future<void> _skip() async {
    final item = _item;
    if (item == null) return;
    await LibraryRepo.markSkipped(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skipped — it will not return.')));
    }
  }

  Future<void> _moreLikeThis() async {
    final item = _item;
    if (item == null) return;
    await LibraryRepo.moreLikeThis(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Noted — more like this soon.')));
    }
  }

  Future<void> _saveNote() async {
    final item = _item;
    if (item == null) return;
    await LibraryRepo.setNote(item.id, _noteController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved on your phone.')));
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _reloadItem() async {
    final item = await LibraryRepo.byId(widget.readId);
    if (!mounted) return;
    setState(() => _item = item);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _watch.stop();
    // Credit remaining seconds, fire-and-forget.
    _flushTime();
    _noteController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: GCol.gold)),
      );
    }
    final bodySize = 19.0 * _fontScale;
    return Scaffold(
      backgroundColor: GCol.bg,
      appBar: AppBar(
        title: Text(item.topic,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 16)),
        actions: [
          IconButton(
              tooltip: 'Smaller text',
              onPressed: () =>
                  setState(() => _fontScale = (_fontScale - .15).clamp(.85, 1.35)),
              icon: const Icon(Icons.text_decrease)),
          IconButton(
              tooltip: 'Larger text',
              onPressed: () =>
                  setState(() => _fontScale = (_fontScale + .15).clamp(.85, 1.35)),
              icon: const Icon(Icons.text_increase)),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(children: [
        const Positioned.fill(child: GoldGlow()),
        const Positioned.fill(child: GrainOverlay()),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'read-${item.id}',
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontFamily: 'Playfair Display',
                        fontSize: 30,
                        height: 1.2,
                        color: GCol.text,
                        fontVariations: [FontVariation('wght', 600)],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${item.source} • ~${item.estimatedMinutes()} min • spent $displayMinutes min today',
                  style: const TextStyle(fontSize: 16, color: GCol.muted),
                ),
                const SizedBox(height: 24),
                SelectionArea(
                  child: Text(
                    item.summary,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: bodySize,
                        height: 1.6,
                        color: GCol.text),
                  ),
                ),
                const SizedBox(height: 28),
                Row(children: [
                  _ReaderAction(
                    icon: Icons.favorite,
                    label: item.liked ? 'Liked' : 'Like',
                    onTap: () => _setLike(!item.liked),
                    active: item.liked,
                  ),
                  const SizedBox(width: 10),
                  _ReaderAction(
                    icon: Icons.replay,
                    label: 'More like\nthis',
                    onTap: _moreLikeThis,
                  ),
                  const SizedBox(width: 10),
                  _ReaderAction(
                    icon: Icons.close,
                    label: 'Skip',
                    onTap: _skip,
                  ),
                ]),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () =>
                      setState(() => _openedNoteField = !_openedNoteField),
                  child: const Text('Add a one-line note',
                      style: TextStyle(fontSize: 16, color: GCol.gold)),
                ),
                if (_openedNoteField) ...[
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    maxLength: 140,
                    style:
                        const TextStyle(fontSize: 16, color: GCol.text),
                    decoration: const InputDecoration(
                      hintText: 'One line, for future you…',
                      hintStyle: TextStyle(fontSize: 16, color: GCol.muted),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: GCol.muted)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  BigButton(label: 'Save note', onTap: _saveNote),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReaderAction extends StatelessWidget {
  const _ReaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? GCol.gold : GCol.text,
        side: BorderSide(
            color: active ? GCol.gold : GCol.muted.withValues(alpha: .5)),
        backgroundColor: GCol.surface.withValues(alpha: .6),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label,
          style: const TextStyle(fontSize: 15, height: 1.15)),
    );
  }
}
