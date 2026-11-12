import 'models.dart';

/// Result of checking a message's balance against the running balance.
sealed class BalanceOutcome {
  const BalanceOutcome();
}

/// The message shows a different balance than expected. The running balance
/// has already been reset to [actual]; [gap] is what is still unexplained.
class BalanceMismatch extends BalanceOutcome {
  const BalanceMismatch(this.provider, {required this.expected, required this.actual, required this.approximate});
  final Provider provider;
  final int expected, actual;

  /// True when foreign card charges with no RWF amount were part of the gap.
  final bool approximate;
  int get gap => actual - expected;
}

/// The only unknown since the last balance was one foreign card charge, so the
/// gap is its RWF cost. The app fills it in and does not flag anything.
class ForeignChargeResolved extends BalanceOutcome {
  const ForeignChargeResolved(this.charge, this.rwfAmount);
  final ParsedMessage charge;
  final int rwfAmount;
}

class _Account {
  _Account(this.expected);
  int expected;
  final List<ParsedMessage> unknown = [];
}

/// Keeps a running balance per account and checks it against every message
/// that shows a balance (see "Balance Check" in the spec).
///
/// Callers must feed messages in transaction-time order and only once each:
/// duplicates, failed and reversed messages are filtered out before this.
class BalanceTracker {
  final Map<Provider, _Account> _accounts = {};

  /// A difference of up to 1 RWF is rounding, not a mismatch.
  static const tolerance = 100;

  int? balanceOf(Provider p) => _accounts[p]?.expected;

  /// Whether the last message given to [apply] showed a balance the check used.
  /// False for no balance, and for Equity's placeholder 0 (see [_placeholderZero]).
  bool lastShowedBalance = false;

  /// Equity sometimes writes the balance as 0 when it does not give it. A 0
  /// when the expected balance is not about 0 is taken as "not shown": the
  /// running balance carries on from the last real figure, and the next real
  /// balance (or a statement) checks it and flags any gap then.
  static bool _placeholderZero(ParsedMessage m, int? expected) =>
      m.provider == Provider.equity && m.balance == 0 && (expected == null || expected.abs() > tolerance);

  /// Starting balance typed in during setup, so the first message is checked too.
  void setStarting(Provider p, int amount) => _accounts[p] = _Account(amount);

  /// A manual entry explaining part of a gap, or any change made by hand.
  void adjust(Provider p, int delta) => _accounts[p]?.expected += delta;

  BalanceOutcome? apply(ParsedMessage m) {
    lastShowedBalance = false;
    final acc = _accounts[m.provider];
    if (acc == null) {
      // No starting balance: the first message with a real one sets it, unchecked.
      if (m.balance != null && !_placeholderZero(m, null)) {
        _accounts[m.provider] = _Account(m.balance!);
        lastShowedBalance = true;
      }
      return null;
    }

    if (m.direction != Direction.none) {
      if (m.rwfKnown) {
        acc.expected += m.balanceDelta;
      } else {
        // shortcut: a foreign Auth Reversal is not matched against its charge, so
        // it counts as a second unknown; match by merchant if this proves noisy.
        acc.unknown.add(m);
      }
    }
    if (m.balance == null || _placeholderZero(m, acc.expected)) return null;
    lastShowedBalance = true;

    final expected = acc.expected;
    final unknown = List.of(acc.unknown);
    acc
      ..expected = m.balance!
      ..unknown.clear();
    final gap = m.balance! - expected;

    if (unknown.length == 1 && unknown.single.direction == Direction.outflow && gap < 0) {
      return ForeignChargeResolved(unknown.single, -gap);
    }
    if (gap.abs() <= tolerance) return null;
    return BalanceMismatch(m.provider, expected: expected, actual: m.balance!, approximate: unknown.isNotEmpty);
  }
}
