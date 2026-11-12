/// Starting categories from the spec. Renaming and adding come later.
const expenseCategories = [
  'Food and drinks',
  'Groceries and shopping',
  'Transport',
  'Airtime',
  'Data and voice bundles',
  'Subscriptions and software',
  'Health and pharmacy',
  'Education and courses',
  'Church and giving',
  'Family and friends',
  'Loan repayments',
  'Fees and charges',
  'Rent and utilities',
  'Personal care and clothing',
  'Entertainment',
  'Savings',
  'Other',
];

const incomeCategories = [
  'Salary',
  'Money from family and friends',
  'Business or side income',
  'Loan received',
  'Refunds and reversals',
  'Other',
];

/// Transfer fees and SMS charges are spending under this category.
const feesCategory = 'Fees and charges';

/// The parser's hint mapped to a starting category, shown first in the picker.
/// It is only a suggestion: the app never saves a category I did not pick.
String? suggestedCategory(String? hint) => switch (hint) {
      null => null,
      'Airtime' => 'Airtime',
      'Data and voice bundles' => 'Data and voice bundles',
      _ when expenseCategories.contains(hint) => hint,
      _ => null,
    };
