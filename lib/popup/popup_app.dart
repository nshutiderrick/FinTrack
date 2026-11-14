import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../platform/alerts.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets/amount.dart';
import 'popup_logic.dart';

/// The floating category card (spec: Category Confirmation Popup). It runs in
/// its own small Flutter engine that the alert listener starts when a payment
/// arrives, so it works while the app itself is closed. My choice is kept on
/// the phone and saved to my account the next time the app opens.
class PopupApp extends StatefulWidget {
  const PopupApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<PopupApp> createState() => _PopupAppState();
}

class _PopupAppState extends State<PopupApp> {
  static const _channel = MethodChannel('expense_tracker/popup');
  PopupItem? _item;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'evaluate') return null;
      final args = (call.arguments as Map).cast<String, Object?>();
      final alert = RawAlert.fromJson((args['alert'] as Map).cast<String, dynamic>());
      final recent = [
        for (final r in (args['recent'] as List? ?? const [])) RawAlert.fromJson((r as Map).cast<String, dynamic>()),
      ];
      final config = PopupConfig.fromMap(((args['config'] as Map?) ?? const {}).cast<String, Object?>());
      final item = evaluatePopup(alert, recent, config);
      setState(() => _item = item);
      return item?.toMap();
    });
    // The listener waits for this before sending the alert.
    _channel.invokeMethod('ready');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: widget.settings,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: widget.settings.themeMode,
        home: Scaffold(
          backgroundColor: Colors.transparent,
          // The card sits at the top, so the keyboard never covers it; do not shrink for it.
          resizeToAvoidBottomInset: false,
          body: _item == null ? const SizedBox.shrink() : _PopupCard(_item!, channel: _channel),
        ),
      ),
    );
  }
}

class _PopupCard extends StatefulWidget {
  const _PopupCard(this.item, {required this.channel});
  final PopupItem item;
  final MethodChannel channel;

  @override
  State<_PopupCard> createState() => _PopupCardState();
}

class _PopupCardState extends State<_PopupCard> with SingleTickerProviderStateMixin {
  final _key = GlobalKey();
  final _description = TextEditingController();
  // The green border keeps circling while the card is on screen.
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    _description.dispose();
    super.dispose();
  }

  bool _showDescription = false;
  bool _showAll = false;
  double _lastHeight = 0;

  /// The window is only as tall as the card, so the app underneath stays usable.
  void _reportHeight() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height + 16;
    if ((h - _lastHeight).abs() < 1) return;
    _lastHeight = h;
    widget.channel.invokeMethod('resize', (h * MediaQuery.of(context).devicePixelRatio).round());
  }

  void _decide({String? category, bool lent = false, bool transfer = false}) {
    final i = widget.item;
    widget.channel.invokeMethod('decide', {
      'alertId': i.alertId,
      'category': category,
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'lent': lent,
      'transfer': transfer,
      'title': i.title,
      'amount': i.amount,
      'time': i.time.millisecondsSinceEpoch,
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
    final i = widget.item;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final shown = _showAll ? i.categories : i.categories.take(6).toList();
    final hidden = SettingsScope.of(context).hideAmounts;
    final amount = i.currency == 'RWF'
        ? Amount(
            i.income ? i.amount : -i.amount,
            signed: true,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          )
        : Text(
            hidden ? '${i.currency} •••••' : '${i.currency} ${(i.amount / 100).toStringAsFixed(2)}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          );

    // Laid out at its natural height (not squeezed into the current window),
    // then the window is resized to fit; so opening the description field
    // grows the card instead of overflowing it.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: CustomPaint(
          key: _key,
          foregroundPainter: _SpinningBorder(_spin, theme.colorScheme.secondary),
          child: Material(
            elevation: 8,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          i.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Padding(padding: const EdgeInsets.only(right: 8), child: amount),
                    ],
                  ),
                  Text(
                    '${i.provider.label} · ${i.income ? 'Pick an income category' : 'Pick a category'}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in shown)
                          ActionChip(
                            label: Text(c),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _decide(category: c),
                          ),
                        if (!_showAll && i.categories.length > shown.length)
                          ActionChip(
                            label: const Text('More…'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _showAll = true),
                          ),
                      ],
                    ),
                  ),
                  if (_showDescription)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
                      child: TextField(
                        controller: _description,
                        autofocus: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Description, then pick a category',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  Wrap(
                    children: [
                      if (!_showDescription)
                        TextButton(
                          onPressed: () => setState(() => _showDescription = true),
                          child: const Text('+ Description'),
                        ),
                      // For my own money moving between my accounts that the app did not catch.
                      TextButton(onPressed: () => _decide(transfer: true), child: const Text('Between my accounts')),
                      if (!i.income && i.isPerson)
                        TextButton(onPressed: () => _decide(lent: true), child: const Text('I lent this')),
                      TextButton(
                        onPressed: () => widget.channel.invokeMethod('dismiss', i.alertId),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A green light running around the card's edge over a faint green outline.
class _SpinningBorder extends CustomPainter {
  _SpinningBorder(this.turn, this.color) : super(repaint: turn);
  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(16));
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0.2), color, color.withValues(alpha: 0.2), color.withValues(alpha: 0.2)],
          stops: const [0, 0.18, 0.4, 1],
          transform: GradientRotation(turn.value * 2 * math.pi),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SpinningBorder old) => old.color != color;
}
