import 'package:flutter/material.dart';

import '../settings.dart';

/// "RWF 3,600" from minor units (360000). When [hidden], the digits are replaced
/// so neither the amount nor its size shows.
String formatRwf(int minor, {bool hidden = false, bool signed = false}) {
  final rwf = (minor / 100).round();
  final sign = rwf < 0 ? '- ' : (signed && rwf > 0 ? '+ ' : '');
  if (hidden) return '${sign}RWF •••••';
  final digits = rwf.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${sign}RWF $digits';
}

/// Every balance or amount on screen goes through this, so the hide toggle covers all of them.
class Amount extends StatelessWidget {
  const Amount(this.minor, {super.key, this.style, this.signed = false});

  final int minor;
  final TextStyle? style;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final hidden = SettingsScope.of(context).hideAmounts;
    return Text(formatRwf(minor, hidden: hidden, signed: signed), style: style);
  }
}

/// The eye button that turns hiding on and off.
class HideAmountsButton extends StatelessWidget {
  const HideAmountsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final hidden = settings.hideAmounts;
    return IconButton(
      tooltip: hidden ? 'Show amounts' : 'Hide amounts',
      icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      onPressed: () => settings.hideAmounts = !hidden,
    );
  }
}
