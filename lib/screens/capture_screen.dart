import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/alerts.dart';

/// Notification access status, the capture-mode switch, and the raw alerts
/// captured so far (see "Capture mode" in the spec).
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.channel = const AlertsChannel()});

  final AlertsChannel channel;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  bool _access = false, _capture = false, _loading = true;
  List<RawAlert> _alerts = [];
  StreamSubscription<RawAlert>? _live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _live = widget.channel.alerts.listen((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live?.cancel();
    super.dispose();
  }

  // Coming back from Android's settings page: access may have just been granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final c = widget.channel;
    final results = await Future.wait([c.isListenerEnabled(), c.isCaptureOn()]);
    final alerts = await c.readCaptured();
    if (!mounted) return;
    setState(() {
      _access = results[0];
      _capture = results[1];
      _alerts = alerts;
      _loading = false;
    });
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_alerts)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_alerts.length} alerts. They include private data, so share with care.')),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear captured alerts?'),
        content: Text('This deletes ${_alerts.length} saved alerts from the phone. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.channel.clearCaptured();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Alert capture')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Notification access'),
                    subtitle: Text(_access ? 'On. Alerts are being read.' : 'Off. The app cannot read alerts yet.'),
                    trailing: _access
                        ? const Text('On')
                        : TextButton(onPressed: widget.channel.openListenerSettings, child: const Text('Turn on')),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    title: const Text('Capture mode'),
                    subtitle: const Text('Save the raw text of money alerts on this phone, to write parsing rules.'),
                    value: _capture,
                    onChanged: (v) async {
                      await widget.channel.setCapture(v);
                      await _refresh();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Captured (${_alerts.length})', style: theme.textTheme.titleMedium)),
                    TextButton(onPressed: _alerts.isEmpty ? null : _copyAll, child: const Text('Copy all')),
                    TextButton(onPressed: _alerts.isEmpty ? null : _clear, child: const Text('Clear')),
                  ],
                ),
                if (_alerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('Nothing yet. New alerts appear here as they arrive.', style: TextStyle(color: muted)),
                  ),
                for (final a in _alerts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.title.isEmpty ? a.package : a.title),
                    subtitle: Text('${a.text}\n${a.package} · ${a.postedAt}'),
                    isThreeLine: true,
                  ),
              ],
            ),
    );
  }
}
