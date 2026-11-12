# Expense Tracker

Personal Android app (Flutter) that tracks money automatically from Equity Bank, MTN MoMo and Airtel Money alerts.

The full spec is in [Expense Tracker (SMS and Notification Based).md](Expense%20Tracker%20(SMS%20and%20Notification%20Based).md). Designs are in the Figma file "Expense Tracker – Prototype".

## Code

- `lib/core/parser.dart`: turns one alert into a parsed transaction (per-provider rules from the spec).
- `lib/core/balance.dart`: running balance per account and the balance mismatch check.
- `lib/core/models.dart`: shared types and the "is this me?" check for own names and numbers.
- `lib/theme.dart`: light and dark colours, matching the Figma tokens.

## Run

```bash
flutter test
```

`test/real_export_test.dart` also runs the parser over a real `sms-*.html` export placed in the project root. Exports are git-ignored because they contain private data.
