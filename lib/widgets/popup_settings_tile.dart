import 'package:flutter/material.dart';

import '../platform/popup_settings.dart';

/// Settings for the floating category pop-up: on or off, and the
/// "Display over other apps" permission it needs (otherwise a notification).
class PopupSettingsTile extends StatefulWidget {
  const PopupSettingsTile({super.key, this.channel = const PopupSettingsChannel()});
  final PopupSettingsChannel channel;

  @override
  State<PopupSettingsTile> createState() => _PopupSettingsTileState();
}

class _PopupSettingsTileState extends State<PopupSettingsTile> with WidgetsBindingObserver {
  bool _on = false;
  bool _overlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's permission page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final on = await widget.channel.isOn();
    final overlay = await widget.channel.canOverlay();
    if (!mounted) return;
    setState(() {
      _on = on;
      _overlay = overlay;
    });
  }

  Future<void> _set(bool on) async {
    await widget.channel.setOn(on);
    if (on) await widget.channel.requestNotifications();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(children: [
      SwitchListTile(
        title: const Text('Category pop-up'),
        subtitle: const Text('When a payment arrives, a small card floats over any app so you can pick its category.'),
        value: _on,
        onChanged: _set,
      ),
      if (_on && !_overlay)
        ListTile(
          title: const Text('Allow "Display over other apps"'),
          subtitle: Text('Until then you get a notification with 2 categories and More instead.', style: TextStyle(color: muted)),
          trailing: TextButton(onPressed: widget.channel.openOverlaySettings, child: const Text('Allow')),
        ),
    ]);
  }
}
