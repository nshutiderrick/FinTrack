# Expense Tracker (SMS and Notification Based)

## Overview

**FinTrack** is a personal Android app that tracks expenses automatically by reading the alerts that arrive from my bank card, MTN Mobile Money, and Airtel Money. It is for my own use only, built because direct bank and MTN API access is not available.

## Goals

- Capture every transaction automatically from alerts, with no manual typing of amounts.
- Separate income, expenses, and transfers between my own accounts.
- Never guess why I spent money: I confirm the category myself.

## How It Works

1. A notification listener reads incoming alerts on the phone: SMS alerts (shown by the messaging app) and push notifications from the Equity mobile app.
2. The app checks the sender to tell apart the bank, MTN Mobile Money, and Airtel Money. Each provider has its own parsing rules.
3. The message wording decides the type of transaction.
4. Expenses start as Pending, and the app sends me a reminder notification to pick a category.
5. Once I confirm the category, the transaction is saved.

## Transaction Types

- **Income:** messages such as received money. These are never added to expenses. They are recorded as money gained.
- **Expense:** money sent out, payments, and card purchases. These start as Pending until I confirm a category.
- **Transfer between my accounts:** for example bank to MTN, or MTN to Airtel when buying data. These are not expenses and not income.
- **Needs review:** any message the parser cannot classify confidently, and any balance mismatch (see Balance Check). The app never guesses.

## Avoiding Double Counting

The same transaction can trigger more than one alert, for example a bank alert and a mobile money alert. To avoid counting twice, the app matches transactions using:

- Reference or transaction number
- Amount
- Time window of a few minutes

A send and a receive with the same amount close together in time are treated as a transfer between my own accounts.

- **Same reference, any time gap:** Equity sometimes sends the exact same alert again hours later. A matching Ref or transaction id is a duplicate no matter how much time has passed.
- **Same id, two messages:** some single transactions produce two messages with one id, for example a MoMo loan repayment ("Your repayment of X" and "X RWF has been used to pay your loan") or an Airtel send through eKash (both carry the same TID). Count them once.

## Balance Check

Most messages show the account balance after the transaction. The app uses it to catch money that moved without a message, such as cash spending, a lost alert or an unexpected fee.

- **Running balance:** the app keeps a balance per account (Equity, MTN, Airtel).
- **Starting balance at install:** during setup, the app asks me for the current balance of each account. The very first transaction after installing is checked against it like any other, so a gap is caught from day one. If I skip an account, its first message with a balance sets the starting figure, and that account is checked from its second message onwards.
- **Expected balance:** last known balance, minus the amount and fees for money out, plus the amount for money in. Every transaction counts here, including pending items, transfers, loans and lending, because they all move money.
- **Check:** when a message shows a balance, the app compares it with the expected balance. If they differ by more than 1 RWF, it flags a **Balance mismatch** showing the expected balance, the actual balance and the difference.
- **Reset:** the running balance is then set to the balance in the message, so the next check starts from the true figure and one gap does not carry into every later message.
- **Resolving:** the mismatch stays in Needs Review. I explain the gap by adding the missing entries by hand (see Manual Entry), and the flag shows how much is still unexplained. It closes when the gap reaches zero, or when I accept it as is (for example an unknown fee).
- **Order:** checks run in transaction time order, not arrival order, because some alerts arrive hours late. A late duplicate never changes the balance.
- **Skipped:** failed, reversed and duplicate messages do not update the balance. Messages without a balance (card Auth, loan approval) only change the expected balance. Cash has no messages, so it has no check.
- **Equity is only partly covered:** in the sample export, Equity transfers and eKash receipts show a balance (newer "successfully sent" messages, "Your new balance is", airtime purchases), but card payments, card reversals and eKash reversals never do. Up to 15 card payments arrived in a row with no balance in between. Card payments only lower the expected Equity balance, and the next message with a balance checks them all at once.
- **Foreign card charges:** USD and EUR card charges do not give an RWF amount, so the expected Equity balance is approximate until the next balance. If one foreign charge is the only unknown, the gap gives its RWF amount: the app fills it in and does not flag a mismatch. With several unknowns, it splits the gap using the exchange rate and asks me to confirm.
- **Equity balance check:** when Equity has gone 7 days or 5 card payments without a balance, a popup asks me to type the balance shown in the Equity app. That figure is a checkpoint like a message balance, and the mismatch check runs against it.
- **Where the balance appears:**

| Provider | Wording |
| --- | --- |
| MTN | "Balance: X RWF", "Balance:X RWF", "New balance: X RWF", "Your new balance: X RWF" |
| Equity | "Balance: RWF X", "Your new balance is RWF X", "balance X" |
| Airtel | "NEW BALANCE isRWF X", "Ubu kuri konti mufite Rwf X", "Ubu mufite RWFX" |

## Statement Import

When balances do not add up, I can upload a statement and the app finds what the alerts missed.

- **Supported:** the MTN MoMo statement PDF ("Momo Statement", from the MoMo app) and the Equity Bank account statement PDF ("Account Statement"). The app tells them apart from the first lines and reads the text on the phone. Nothing is uploaded.
- **MoMo statement rows:** transaction id, status, type (TRANSFER, PAYMENT, CUSTOM_PAYMENT, DEBIT, CASH_IN), date and time, from (number and name), to (number or merchant code and name), amount, fee and balance after. Only SUCCESSFUL rows count. A row is money out when "from" is my own number.
- **Equity statement rows:** description, payment reference(s), value date (no time), one amount, and balance. Money in or out is worked out from the balance change. Descriptions seen: `APP/MTN/<phone>/<ref>/<name>/` (send to MoMo), `APP/<NAME>/` (send to a person), `MC-<merchant> /PURC` (card payment, in RWF), `RNDPS eKash/...` (eKash transfer), `TPGYBILL <phone> <MTN id>` (money in from MoMo), `REVERSED : ...` (reversal), and charge lines.
- **Matching to what the app already has:** first by reference (MoMo transaction id = the SMS TxId or FT Id; Equity `A…` MTN ref and `S…` eKash ref = the SMS Ref), then by same amount and direction close in time (2 minutes for MoMo, the same day for Equity).
- **What it fixes:**
  - **Missed transactions:** statement rows with no matching alert are added as "From statement" and go through the normal flow (Pending category, transfer matching).
  - **Unknown "payment to EQUITY BANK RWANDA with token":** an Equity `TPGYBILL` row carries the MoMo transaction id, so the MoMo payment is confirmed as a transfer to my own account.
  - **Foreign card charges:** Equity statement card rows give the RWF amount, which replaces the "approximate" USD or EUR amount.
  - **Balance mismatches:** every statement row has a balance, so each gap closes once the missing rows are added.
- **Duplicates:** importing the same or an overlapping statement twice adds nothing new, because rows already known are matched by reference.
- **Summary after import:** rows read, already known, added, transfers confirmed, foreign amounts filled, and mismatches closed.

## Pending and Category Flow

- A new expense is saved as Pending.
- The app notifies me that an item is waiting for a category.
- I choose the category, and only then is the expense finalized and saved.

## Category Confirmation Popup

When a new expense is saved as Pending, a small floating popup appears over whatever app I am using. It does not take over the whole screen.

- **Shows:** the amount, who or what it was paid to, and the provider (bank, MTN or Airtel).
- **Optional extras:** "+ Description" and "+ Photo" buttons let me add both before saving. Neither is required, and both can be added or changed later from the expense's detail screen.
- **Buttons:** one tap per category, plus a Skip button that leaves the item pending. For money sent to a person, there is also an "I lent this" button that records it as a loan to them instead of spending (see Loans).
- **Why floating:** a notification is easy to ignore and forget, while a popup in front of me is hard to miss.
- **Needs:** the "Display over other apps" permission, granted once on my phone.
- **Fallback:** if the permission is missing or the popup cannot show, send a notification with the category buttons inside it, so I can confirm without opening the app. Android allows only 3 buttons per notification, so it shows the 2 most likely categories and a More button that opens the full popup.
- **Reminders:** if I skip or dismiss the popup, the item stays Pending and the popup returns after a short delay.

### Other popups

The same floating card is used for every question the app needs answered. Each one has a Later button that leaves the item in Needs Review.

| Popup | When it shows | Buttons |
| --- | --- | --- |
| Card purchase | A card payment to a shop. Foreign charges show the original currency. A repeating merchant offers "Track as subscription". | Categories, Save (no "I lent this") |
| Lent details | After tapping "I lent this" | Optional due date and note, reminder on or off, Save loan |
| Repayment | Money arrives from someone who owes me | Link to loan, or It is income |
| Income | Money received from a person or from abroad | Income categories, Save |
| Balance mismatch | A message balance differs from the expected balance | Add what I spent, Review later |
| Equity balance check | Equity has gone too long without a balance (see Balance Check) | Type the balance, Save |
| Renewal reminder | 1 or 2 days before a subscription renews | Keep it, I cancelled it |
| Missed renewal | No payment a few days after the renewal date, or a failed charge | Mark cancelled, I will pay |

Loan due reminders and "items still need a category" reminders are ordinary notifications, not popups.

## Starting Categories

This is the first list. I will add or rename categories later, so the app should let me do that.

**Expense categories**

- Food and drinks
- Groceries and shopping
- Transport
- Airtime
- Data and voice bundles
- Subscriptions and software
- Health and pharmacy
- Education and courses
- Church and giving
- Family and friends (money sent to people)
- Loan repayments
- Fees and charges (transfer fees, SMS alert charges)
- Rent and utilities
- Personal care and clothing
- Entertainment
- Savings
- Other

**Income categories**

- Salary
- Money from family and friends
- Business or side income
- Loan received
- Refunds and reversals
- Other

## Manual Entry

I can add an income or expense by hand for anything the app did not catch, such as cash payments.

- **Fields:** type (income or expense), amount, category, date and time, an optional description (what it was, such as "rice 2 kg, cooking oil"), and an optional photo (a receipt or the item, taken with the camera or picked from the gallery).
- **Account:** I pick where it came from: Equity, MTN, Airtel or Cash.
- **Skips Pending:** since I choose the category myself, a manual entry is saved straight away.
- **Edit and delete:** I can fix or remove any entry later, including ones the app added automatically. Each expense has a detail screen showing its category, account, date, fee, reference, description and photo, where any of these can be changed.
- **Duplicate check:** if a manual entry matches an automatic one with the same amount at nearly the same time, the app warns me before saving.
- **Explaining a balance mismatch:** from a Balance mismatch flag I can add the missing entries directly. They are dated before the message that showed the gap, and each one reduces the unexplained amount on the flag.

## Reports and Summaries

A reports screen shows how much I brought in and how much I spent, so I can see where my money goes.

- **Period:** I can view a single day, a single week (Monday to Sunday), a single month, a single year, or a custom date range.
- **Account filter:** an "All accounts / Equity / MTN / Airtel / Cash" choice limits every figure, list and chart to one account. The same filter is on Home and on the transaction lists, and the app remembers my last choice. Transfers between my accounts are left out of "All accounts" but appear as money in or out when one account is selected.
- **Per account:** a breakdown showing income, spending and the closing balance of each account for the chosen period, side by side.
- **Hidden accounts:** in Settings → Accounts shown, any account can be switched off. A hidden account keeps recording in the background: alerts are still read, matched and balance-checked, so nothing is missed. Home, Reports, the account filter and Needs Review leave it out, and the totals recalculate from the accounts still shown. A transfer between a shown and a hidden account appears as money moved in or out, not as income or spending. Switching the account back on brings back its full history and current balance, with no gap. At least one account always stays shown. The choice is kept on the phone.
- **Totals:** total income, total spent, and the difference between them for the chosen period.
- **Top spending:** my expense categories ranked from largest to smallest, with the amount and percentage for each. The top category is shown first.
- **Top income:** the same ranking for income, so I can see where money comes from.
- **Trends:** a simple chart comparing months, so I can see whether I spend more or less over time.
- **Drill down:** tapping a category shows the individual transactions behind it.
- **Trends by day and week:** besides months, the chart can compare days within a week or weeks within a month.

- **Filters as drop-downs:** the period (Day, Week, Month, Year, Custom range) and the account are two drop-down menus at the top; arrows step to the previous or next period.

## Transactions

A Transactions page (from "See all" on Home) lists every transaction: expenses, income and transfers between my accounts.

- **Sort:** newest or oldest first, amount high to low or low to high, name A to Z or Z to A.
- **Filter:** by one or more categories, plus "Between my accounts", "No category yet" and "Loans". The account filter and hidden accounts apply as on Home.
- **Search:** by name or description. The count and the money in and out of what is shown appear above the list.

### What counts in the totals

- Only confirmed expenses count. Pending items are shown separately until I pick a category.
- Transfers between my own accounts are left out, so they do not inflate income or spending.
- Transfer fees and SMS alert charges count as expenses under Fees and charges.
- Loans received are shown as Loan income, and repayments as Loan repayments, so borrowed money does not look like earned money.

## People Tracking

The app keeps track of who I received money from and who I sent money to.

- **Captured from messages:** the name and phone number that appear in person-to-person transfers, for example "transferred to \[name\] (\[phone\])" and "received from \[name\]". Merchants and shops are not treated as people.
- **Contacts list:** each person is saved once, with their name and phone number, and every transfer is linked to them. The phone number is the unique key, because the same person can appear with slightly different spellings of their name.
- **Nicknames:** I can rename a contact, for example to a nickname or relationship such as Mom or Landlord. A rename applies to all past and future transfers with that number.
- **Masked numbers:** some messages show a partly hidden number. When only the last digits are visible, match them to an existing contact, and send unmatched ones to Needs Review.
- **Person screen:** tapping a person shows everything I received from them and sent to them, with totals and dates, and what they owe me or I owe them.
- **Reports:** top people I send money to, and top people who send money to me, for a chosen month or year.
- **Own accounts:** my own name and my own phone numbers are never listed as people, since those are transfers between my accounts.
- **Manual entry:** when I add an income or expense by hand, I can optionally attach a contact.

## Loans

A dedicated Loans section tracks money I owe and money owed to me. It has two tabs.

### Money I owe

- **App loans:** loans from MoFaya, MoFlex, YABX and similar are created automatically from the approval message, with the amount, the date, and the repayment message that closes the loan.
- **Loans from people:** I can add a loan from a friend or anyone else by hand, with the lender's name, amount and due date.
- **Fields:** lender, amount borrowed, total to repay (including interest or fees), due date, amount repaid so far, and what is left.
- **Reminders:** a notification a few days before the due date and again on the due date. An overdue loan is highlighted.
- **Repayments:** a payment that matches the lender is linked to the loan automatically and reduces what is left. The loan is marked Closed when it reaches zero.
- **Not income:** borrowed money is never counted as income, and repayments are not counted as ordinary spending.

### Money owed to me

- **Lending from the popup:** when I send money to a person, the category popup has an extra "I lent this" button next to the categories.
- **Effect:** lent money still leaves my balance, but it is not counted as spending in reports. It is added to the Money owed to me list instead.
- **Asking for details:** after tapping "I lent this", I can set an optional due date and a note.
- **Per person:** the list is grouped by person, with the total they owe me and each loan under it.
- **Repayments to me:** when that person sends money back, the app suggests linking it to the loan. I confirm in the popup, and the amount owed goes down. This is also not counted as income.
- **Partial payments:** a loan can be paid back in several parts, and the app shows what is still unpaid.
- **Manual entry:** I can also add a loan to someone by hand, for example if I lent cash.
- **Reminders:** an optional reminder when the due date arrives or when a loan has been unpaid for a long time.

### Reports

- Totals for money I owe, money owed to me, and what is overdue.
- Loans are kept out of the income and spending totals, so the Reports figures stay accurate.

## Subscriptions

A dedicated Subscriptions section tracks what I pay for regularly and reminds me before each renewal, so I can cancel in time.

- **Detection:** a card charge from the same merchant that repeats about every month or year is suggested as a subscription, and I confirm it. Examples from my messages: Anthropic Claude, FundedNext, and CapCut.
- **Manual add:** I can also add a subscription by hand, for example one paid with mobile money, with the name, amount, how often it renews, and the next renewal date.
- **Fields:** name, amount, currency, billing cycle (weekly, monthly, yearly), date of the last payment, next renewal date, and which account pays for it.
- **Next renewal:** worked out from the last payment date plus the billing cycle. Each new matching payment updates it automatically.
- **Reminders:** a notification one or two days before the renewal date, chosen per subscription. The reminder says the name and amount, so I can decide whether to keep it.
- **Actions on the reminder:** Keep, which sets the next cycle, or Cancel, which marks the subscription as cancelled and stops reminders.
- **Payment history:** each subscription lists every payment found, with date and amount.
- **Foreign currency:** charges in USD or EUR are shown in their original currency, with the amount in RWF when the message gives it.
- **Failed payments:** a charge that failed for insufficient funds is flagged on the subscription, because the service may cancel or retry it.
- **Missed renewal:** if the expected payment does not arrive within a few days of the renewal date, the app asks whether I cancelled it.
- **Totals:** monthly and yearly cost of all active subscriptions, shown on the Subscriptions screen and in Reports.
- **Categories:** subscription payments count as expenses under Subscriptions and software, and I do not need to confirm the category again for a subscription I have already approved.

## Tech Choice

The app is built with Flutter, targeting Android only.

- **Native pieces:** three features need small native Kotlin code that Flutter calls through platform channels: the notification listener, the floating popup, and the background service that keeps the listener running.
- **Plan for it early:** set up these native parts at the start of the project, not at the end.
- **Local storage:** keep a copy of the data on the phone so the app works offline, and sync it to the cloud when the phone is online.
- **Battery settings:** the app should ask me to turn off battery optimization for it, so Android does not stop the listener in the background.
- **Hide amounts:** an eye button on Home (and a switch in Settings) replaces every balance and amount with "RWF •••••", for when someone can see the screen. It stays on until I turn it off.
- **Updates keep my data:** a new version installs over the old one instead of replacing it. This needs the same package id, a version number that only goes up, and the same signing key. The daily app has its own permanent key (`android/expense-tracker-release.jks` with `android/key.properties`), kept out of git and backed up: if it is lost, updates can no longer install over the app and it would have to be reinstalled from scratch. Data synced to Firebase survives even that.
- **Two apps during development:** "FinTrack Capture" (capture mode on, keeps the alerts saved so far; earlier called ET Capture) and "FinTrack" (daily use, capture off; earlier called Expense Tracker) are installed side by side. Renaming does not change the package ids, so updates still keep the data. Both read alerts; only ET Capture saves raw text.
- **Look:** black and white, with #024944 for text buttons. Settings has a System / Light / Dark choice; System follows the phone setting. In dark mode, text buttons use a lighter tint of the same green (#5FB3A9), because #024944 is too dark to read on black.
- **Designs:** the Figma prototype has light and dark versions of every app screen and popup.

### Cloud Database (Firebase)

Data is stored in Firebase so it survives a lost, broken or reset phone and stays in sync with the Flutter app.

- **Database:** Cloud Firestore, using the official Flutter packages from FlutterFire.
- **Offline first:** Firestore keeps a local cache, so transactions are saved on the phone and sync automatically when there is a connection.
- **Sign-in:** Firebase Authentication, so only I can read my data. Google sign-in is the simplest option.
- **Security rules:** each user can read and write only their own documents. Nothing is public.
- **Stored data:** transactions, categories, contacts and settings. Raw message text is not uploaded, only the parsed fields: amount, type, provider, merchant, category, date, reference number, the balance shown after the transaction, my optional description and photo, and for person-to-person transfers the other person's name and phone number.
- **Privacy:** names and phone numbers are stored only for transfers to or from people, not for shop or merchant payments. They live only in my private Firebase account, protected by the security rules above.
- **Reports:** monthly and yearly totals can be calculated from the transactions in the app, so no extra server is needed.
- **Descriptions:** a normal text field on the transaction, stored in Firestore.
- **Cost:** the free Spark plan is enough for one person's Firestore data. Photos do not use Firebase Storage, so no paid plan is needed.

### Photo Storage (Cloudinary)

Expense photos (receipts or items) are stored in Cloudinary, not Firebase.

- **Upload:** the app compresses the photo on the phone (about 200 KB), keeps a local copy, and uploads it straight to Cloudinary using an unsigned upload preset when online. Firestore stores only the returned `secure_url` and `public_id` on the transaction.
- **Upload preset settings:** a fixed folder (`expense-tracker/receipts`), images only (jpg, png, webp), a maximum file size of about 5 MB, a random `public_id`, and no overwrite.
- **No secret in the app:** the Cloudinary API secret is never put in the app. The cloud name and the unsigned preset name are not secret and live in the app's config.
- **Privacy trade-off:** with unsigned uploads, an image can be opened by anyone who has its URL. The random `public_id` makes a URL practically impossible to guess, but receipts are not protected by the Firebase "only me" rules. Making images private would need signed uploads, which require a small server to hold the secret.
- **Deleting:** removing a photo in the app unlinks it from the transaction right away. The image file itself can be deleted from the Cloudinary dashboard, because deleting by API also needs the secret. A later server or Cloud Function could automate this.
- **Offline:** photos taken offline wait in an upload queue and are sent when the phone is online, like Firestore writes.
- **Cost:** Cloudinary's free plan has a monthly credit allowance that a few compressed receipts a day will not come close to.

## Approach to Permissions

- Reading messages: Android notification listener, which reads alerts instead of the SMS inbox. Confirming categories: a floating popup, using the display over other apps permission, with notification buttons as the fallback.
- Since the app is only for me, it is installed directly on my phone rather than through Google Play, so Play Store SMS restrictions do not apply.
- Fallback options: SMS permission, an SMS forwarder to a sheet or email, or manually pasting a message into the app.

## Parsing Rules

These rules come from an export of 1,730 real messages (Sep 2025 to Nov 2026): MTN 79%, Equity 16%, Airtel 5%. Each provider is told apart by sender name, and each has its own wording.

### MTN Mobile Money (sender `M-Money`)

| Type | Wording to look for |
| --- | --- |
| Expense | "Your payment of X RWF to \[merchant\] \[code\] was completed" or "has been completed" (add the Fee) |
| Expense | "X RWF transferred to \[name\] (\[phone\])" (add the Fee). Three wordings over time: ".Fee: 20RWF", ".Fee : 20 RWF", and the oldest "from \[account\] ... Fee was: 20 RWF" |
| Expense | "A transaction of X RWF by Data Bundle MTN" or "Voice Pack MTN", and other billers such as IREMBO or Flutterwave |
| Expense | "Your payment of X RWF to Airtime with token" (airtime) |
| Expense | "Your payment of X RWF to \[other person\] at EQUITY BANK with token" (money sent to someone's bank account) |
| Expense | "via agent: \[agent\] ... withdrawn X RWF" (cash withdrawal, add the Fee). Older wording starts "You \[own name\] have via agent" |
| Income | "You have received X RWF from \[name\] (\[masked phone\])" |
| Income | "received ... from THUNES LTD", "Onafriq" or "ECOBANK": money from abroad. The real sender is in "Message from sender: \[name\]", so link that name, not the company |
| Transfer | "You have received X RWF from \[own name\]" with "Equity B2C" or "FSP:EquityBank" in the sender message (Equity to MTN) |
| Transfer | "Your payment of X RWF to \[own name\] at EQUITY BANK with token" or "to eKash with token" (MTN to Equity) |
| Transfer | "Your payment of X RWF to Mokash Savings" (to savings) |
| Loan | See Loans below |
| Ignore | One-time password messages |
| Ignore | Anything containing "failed" or "FAILED", but pass it to Subscriptions if it matches one (see Failed messages) |

### Equity Bank (sender `EQUITYBANK`)

| Type | Wording to look for |
| --- | --- |
| Expense | "Auth for card ... Amt: RWF/USD/EUR X Details: \[merchant\]" |
| Expense | "X RWF has been successfully sent to \[name\]" or "was successfully sent to" (charges and the 4 RWF SMS fee are in the same message) |
| Expense | "Your airtime purchase of X RWF for Airtel \[number\] was successful" |
| Income | "You have received ...", "You have just received ... on eKash", and "You have been credited with RWF X" |
| Transfer | Any of the above where the other party is my own name, for example "received ... via incoming transfer from \[own name\]" |
| Ignore | "Confirmed. Request to send..." (count only the later "successfully sent") |
| Cancel | "Auth Reversal" cancels the matching earlier Auth (same merchant and amount) |
| Cancel | "We issued a reversal of X RWF ... Ref." and "Transfer request unsuccessful ... reversed back" cancel the matching earlier send |
| Ignore | "failed due to insufficient funds", but pass it to Subscriptions (see Failed messages) |
| Ignore | "Debit for card ... Amt: 0.00 Details: Regular Charge" |
| Ignore | OTP, verification code and "Validation complete" messages |
| Ignore | Surveys, maintenance, security and service notices |
| Ignore | Kinyarwanda copies (they start "Munyamuryango" or "Banyamuryango") |

### Equity mobile app (push notifications)

The Equity app sends its own notifications, separate from the `EQUITYBANK` SMS. They are read by the same listener and recognised by the app's package name.

- **Why:** Equity SMS often leave out the balance. Card payments never show it, and before about September 2026 eKash receipts sent no SMS at all. In the sample export only 42 Equity messages showed a balance, and gaps of up to RWF 731,508 went unexplained. If the app's notifications include balances or the missing transactions, they fill that gap.
- **App and wording:** package `ke.co.equitygroup.equitymobile`, notification title "OneEquity". The first sample (Nov 11, 2026) is word for word the same as the SMS, balance included: "You have just received RWF 5000.00 …, REF S3574951 11 Nov 2026 on eKash. Your new balance is RWF 6540.00". So these notifications go through the Equity SMS rules. Capture mode keeps collecting, to confirm card payments and transfers use the same wording.
- **Double alerts:** most transactions will arrive both as an SMS and as an app notification. They are matched by reference first, then by the same amount within a few seconds, and counted once.
- **Android limits:** Android 15 hides one-time codes and some notifications marked sensitive from listener apps, and some banking apps hide amounts on the lock screen. What comes through must be checked on my phone.

### Capture mode

A setting that saves the raw text of every relevant notification, so rules can be written from real samples, as was done for the SMS export.

- **What is saved:** notifications from the SMS senders `M-Money`, `EQUITYBANK` and `AirtelMoney`, any notification from an app whose package name contains "equity", and any other notification mentioning RWF. For each one: app package, title, text and time.
- **Where:** a file inside the app's private storage on the phone. It is never uploaded, and it can be viewed, shared by me on purpose, or cleared from the app.
- **When:** on by default during development, off in normal use.

### Airtel Money (sender `AirtelMoney`)

Airtel messages are mostly in Kinyarwanda. Success words: "Byemeye", "Byakunze", "byagenze neza".

| Type | Wording to look for |
| --- | --- |
| Expense | "Kugura Inite ya Rwf X" (airtime), "Kugura Pack ya Rwf X" (bundle) |
| Expense | "Kohereza Rwf X kuri \[name\] \[phone\] muri MTN" (send money, add "IGICIRO cya serivisi") |
| Expense | "Kwishyura RWFX kuri \[merchant\]" (payment). If it shares a TID with a Kohereza message, it is the same transaction |
| Transfer in | "You have received RWF X from \[own name\] ... in MTN Rwanda" |
| Income | "You have received RWF X from \[other name\] ... in MTN Rwanda" |
| Ignore | "ntibyakunze", "Transaction Failed" and wrong-PIN messages ("PIN washyizemo siyo", "Washyizemo ibitaribyo") |

### Transfers between my own accounts

- My own name and phone numbers appear as the other party, so "from" or "to" my own name or numbers means a transfer, not income or an expense.
- My name appears in several forms: first name first or surname first, double spaces, and sometimes written twice. Compare names after removing extra spaces and ignoring word order.
- My own names, phone numbers and account numbers are set once in Settings, not written into the code.
- The two sides arrive seconds apart with the same amount. Examples: Equity "sent to \[own name\] ... MTN Ref" with MTN "Transfer from \[own name\] Equity B2C", MTN "payment to \[own name\] at EQUITY BANK with token" with Equity "You have just received ... on eKash", and MTN "payment to eKash" with Airtel "You have received ... in MTN Rwanda".
- Match on amount within about 15 seconds, or on a shared Ref number.
- The Airtel airtime or bundle purchase that follows is the real expense.

### Loans

Each loan event produces two or three messages. Link them by the loan id.

| Event | Messages | Count as |
| --- | --- | --- |
| Approval | "Your loan application of X RWF with id N ... for MoFaya/MoFlex ... approved" and "You have received X RWF from MoFaya Loans" in the same second | One loan received |
| Repayment | "Your repayment of X RWF for loan id N to \[lender\]" and "X RWF has been used to pay your loan" (same Financial transaction id) | One repayment |
| Closure | "Your loan BPR-LOANS-... with id N ... has been closed" (MoFaya) or "YABX-LOANS-..." (MoFlex) | Marks the loan Closed |

- Interest seen so far: 80,000 repaid as 87,200 and 30,000 as 32,700 (9%), 25,000 as 27,500 (10%).
- Other lenders: Mokash Loan ("received from Mokash Loan Account", "payment to Mokash Loan") and K'Avance overdraft from MoMoAdvance.

### Failed messages

Failed messages never count as spending or change the balance. A failed card charge to a known subscription (seen for CapCut and Google One) still sets the "failed payment" flag on that subscription.

### Special cases

- **"Payment to EQUITY BANK with token":** the recipient is named in the message. My own name means a transfer, and anyone else's name means an expense. Send it to Needs Review only when no name is present.
- **Payment codes used by people:** some "Your payment of X RWF to \[first name\] \[code\]" payees are people, not shops. Treat them as merchants, but let me mark a payee as a person, and remember that choice.
- **Card dates:** the date inside an Equity card Auth message can be several hours off from when it arrived. For card messages, use the time the alert arrived. For transfers, use the date and time in the message, because those alerts can arrive late.
- **Changing formats:** amounts appear as "3,600", "190,000", "2 000.00", "4000", "RWF190000" and "isRWF 5080". Dates appear as "2026-11-10 17:21:33", "2026-11-04T20:53:45+02:00", "07/11/2026 at 12:49 CAT", "04 Nov 2026" and "13-Feb-26". The parser must accept all of these.
- **Text encoding:** names with accents (such as "Irène") must be read as UTF-8.

## Next Steps

1. ~~Export sample messages~~ and ~~write the parsing rules per provider~~ (done, see Parsing Rules).
2. Turn the export into parser test cases, with names, phone numbers and account numbers replaced by fake ones.
3. Set up the Flutter project and the native parts: notification listener, floating popup, background service.
4. Build the parser, classifier, pending list and reminder notification.
5. Add duplicate and transfer matching, and the balance check.

## Open Questions

- Which categories to add or rename beyond the starting list.
- Whether a payee used many times (such as a supermarket) should get its last category pre-selected in the popup, while still needing my tap to confirm.
