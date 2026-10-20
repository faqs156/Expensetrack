import 'package:flutter/material.dart';

import '../models/category.dart';

List<ExpenseCategory> defaultCategories() {
  const expense = CategoryKind.expense;
  const income = CategoryKind.income;

  final expenses = <(String, String, int)>[
    ('Food & Dining', 'food', 0xFFF97316),
    ('Groceries', 'groceries', 0xFF84CC16),
    ('Transport', 'transport', 0xFF3B82F6),
    ('Shopping', 'shopping', 0xFFEC4899),
    ('Bills & Utilities', 'bills', 0xFF8B5CF6),
    ('Rent', 'rent', 0xFF6366F1),
    ('Health', 'health', 0xFFEF4444),
    ('Entertainment', 'entertainment', 0xFF14B8A6),
    ('Travel', 'travel', 0xFF0EA5E9),
    ('Education', 'education', 0xFFA855F7),
    ('Personal Care', 'personal_care', 0xFFF43F5E),
    ('Other', 'other_expense', 0xFF64748B),
  ];

  final incomes = <(String, String, int)>[
    ('Salary', 'salary', 0xFF059669),
    ('Freelance', 'freelance', 0xFF10B981),
    ('Investments', 'investments', 0xFF0D9488),
    ('Gifts', 'gifts', 0xFF22C55E),
    ('Other Income', 'other_income', 0xFF64748B),
  ];

  final list = <ExpenseCategory>[];
  var order = 0;
  for (final e in expenses) {
    list.add(
      ExpenseCategory(
        id: 'def_${e.$2}',
        name: e.$1,
        kind: expense,
        iconKey: e.$2,
        colorValue: e.$3,
        isDefault: true,
        sortOrder: order++,
      ),
    );
  }
  order = 0;
  for (final e in incomes) {
    list.add(
      ExpenseCategory(
        id: 'def_${e.$2}',
        name: e.$1,
        kind: income,
        iconKey: e.$2,
        colorValue: e.$3,
        isDefault: true,
        sortOrder: order++,
      ),
    );
  }
  return list;
}

IconData iconForKey(String key) {
  return switch (key) {
    'food' => Icons.restaurant_rounded,
    'groceries' => Icons.shopping_basket_rounded,
    'transport' => Icons.directions_car_rounded,
    'shopping' => Icons.shopping_bag_rounded,
    'bills' => Icons.receipt_long_rounded,
    'rent' => Icons.home_rounded,
    'health' => Icons.favorite_rounded,
    'entertainment' => Icons.movie_rounded,
    'travel' => Icons.flight_rounded,
    'education' => Icons.school_rounded,
    'personal_care' => Icons.spa_rounded,
    'other_expense' => Icons.more_horiz_rounded,
    'salary' => Icons.payments_rounded,
    'freelance' => Icons.laptop_mac_rounded,
    'investments' => Icons.trending_up_rounded,
    'gifts' => Icons.card_giftcard_rounded,
    'other_income' => Icons.add_circle_outline_rounded,
    'custom' => Icons.label_rounded,
    _ => Icons.category_rounded,
  };
}
