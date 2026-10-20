import 'package:flutter/foundation.dart';

import '../core/date_keys.dart';
import '../data/models/app_settings.dart';
import '../data/models/budget.dart';
import '../data/models/category.dart';
import '../data/models/transaction.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/services/backup_service.dart';
import '../data/services/csv_service.dart';
import '../data/services/data_survival_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    CategoryRepository? categories,
    TransactionRepository? transactions,
    BudgetRepository? budgets,
    SettingsRepository? settings,
    CsvService? csv,
    BackupService? backup,
    DataSurvivalService? survival,
  })  : _categories = categories ?? CategoryRepository(),
        _transactions = transactions ?? TransactionRepository(),
        _budgets = budgets ?? BudgetRepository(),
        _settingsRepo = settings ?? SettingsRepository(),
        _backup = backup ?? BackupService(),
        _survival = survival ?? DataSurvivalService() {
    _csv = csv ??
        CsvService(transactions: _transactions, categories: _categories);
  }

  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final BudgetRepository _budgets;
  final SettingsRepository _settingsRepo;
  late final CsvService _csv;
  final BackupService _backup;
  final DataSurvivalService _survival;

  bool loading = true;
  String? error;
  AppSettings settings = const AppSettings();
  List<ExpenseCategory> categories = [];
  DateTime selectedMonth = DateKeys.startOfMonth(DateTime.now());
  MonthTotals monthTotals = const MonthTotals(expensePaise: 0, incomePaise: 0);
  List<CategorySpend> categoryBreakdown = [];
  List<DailySpend> dailySpend = [];
  List<Transaction> recent = [];
  MonthlyBudget budget = const MonthlyBudget(monthKey: '');
  BudgetStatus overallBudgetStatus =
      const BudgetStatus(budgetPaise: 0, spentPaise: 0);

  TransactionFilter txFilter = const TransactionFilter();
  List<Transaction> filteredTransactions = [];
  MonthTotals filteredTotals =
      const MonthTotals(expensePaise: 0, incomePaise: 0);

  MonthTotals previousMonthTotals =
      const MonthTotals(expensePaise: 0, incomePaise: 0);
  bool previousMonthHasData = false;

  /// Non-null when a surviving Documents backup was found on an empty database.
  String? pendingRestoreJson;
  bool restoreOfferDismissed = false;

  Future<void> init() async {
    loading = true;
    error = null;
    pendingRestoreJson = null;
    notifyListeners();
    try {
      settings = await _settingsRepo.load();
      categories = await _categories.getAll();
      await refreshDashboard();
      await refreshTransactions();

      final count = await _transactions.countAll();
      if (count == 0 && !restoreOfferDismissed) {
        final surviving = await _survival.readSurvivingBackup();
        if (surviving != null && surviving.trim().isNotEmpty) {
          pendingRestoreJson = surviving;
        }
      }

      // Keep a fresh surviving copy whenever the app starts with data.
      if (count > 0) {
        _persistSurvival();
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void dismissRestoreOffer() {
    pendingRestoreJson = null;
    restoreOfferDismissed = true;
    notifyListeners();
  }

  Future<void> acceptPendingRestore() async {
    final json = pendingRestoreJson;
    if (json == null) return;
    pendingRestoreJson = null;
    restoreOfferDismissed = true;
    await restoreBackup(json);
  }

  void _persistSurvival() {
    _survival.scheduleAfterChange(() => _backup.createBackupJson());
  }

  Future<void> refreshDashboard() async {
    monthTotals = await _transactions.monthTotals(selectedMonth);
    categoryBreakdown = await _transactions.categoryBreakdown(selectedMonth);
    dailySpend = await _transactions.dailyExpenses(selectedMonth);
    recent = await _transactions.recent(limit: 8, month: selectedMonth);

    final key = DateKeys.monthKey(selectedMonth);
    budget = await _budgets.getForMonth(key);
    var overall = budget.overallPaise;
    if (overall <= 0 && settings.defaultOverallBudgetPaise > 0) {
      overall = settings.defaultOverallBudgetPaise;
    }
    overallBudgetStatus = BudgetStatus(
      budgetPaise: overall,
      spentPaise: monthTotals.expensePaise,
    );

    final prev = DateKeys.previousMonth(selectedMonth);
    previousMonthTotals = await _transactions.monthTotals(prev);
    previousMonthHasData = previousMonthTotals.expensePaise > 0 ||
        previousMonthTotals.incomePaise > 0;

    notifyListeners();
  }

  Future<void> refreshTransactions() async {
    filteredTransactions = await _transactions.query(txFilter);
    var expense = 0;
    var income = 0;
    for (final t in filteredTransactions) {
      if (t.type == TxType.expense) {
        expense += t.amountPaise;
      } else {
        income += t.amountPaise;
      }
    }
    filteredTotals = MonthTotals(expensePaise: expense, incomePaise: income);
    notifyListeners();
  }

  Future<void> setSelectedMonth(DateTime month) async {
    selectedMonth = DateKeys.startOfMonth(month);
    await refreshDashboard();
  }

  Future<void> setTxFilter(TransactionFilter filter) async {
    txFilter = filter;
    await refreshTransactions();
  }

  List<ExpenseCategory> categoriesFor(TxType type) {
    final kind =
        type == TxType.expense ? CategoryKind.expense : CategoryKind.income;
    return categories.where((c) => c.kind == kind && !c.isArchived).toList();
  }

  Future<Transaction> addTransaction({
    required int amountPaise,
    required TxType type,
    required String categoryId,
    required DateTime occurredAt,
    required PaymentMethod paymentMethod,
    String? description,
  }) async {
    final tx = await _transactions.insert(
      amountPaise: amountPaise,
      type: type,
      categoryId: categoryId,
      occurredAt: occurredAt,
      paymentMethod: paymentMethod,
      description: description,
    );
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
    return tx;
  }

  Future<void> updateTransaction(Transaction tx) async {
    await _transactions.update(tx);
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
  }

  Future<void> deleteTransaction(String id) async {
    await _transactions.delete(id);
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
  }

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await _settingsRepo.save(next);
    notifyListeners();
    await refreshDashboard();
    _persistSurvival();
  }

  Future<void> setOverallBudget(int paise) async {
    final key = DateKeys.monthKey(selectedMonth);
    await _budgets.setOverall(key, paise);
    await _settingsRepo.save(
      settings.copyWith(defaultOverallBudgetPaise: paise),
    );
    settings = settings.copyWith(defaultOverallBudgetPaise: paise);
    await refreshDashboard();
    _persistSurvival();
  }

  Future<void> setCategoryBudget(String categoryId, int paise) async {
    final key = DateKeys.monthKey(selectedMonth);
    await _budgets.setCategory(key, categoryId, paise);
    await refreshDashboard();
    _persistSurvival();
  }

  Future<ExpenseCategory> createCategory({
    required String name,
    required CategoryKind kind,
  }) async {
    final c = await _categories.create(name: name, kind: kind);
    categories = await _categories.getAll();
    notifyListeners();
    _persistSurvival();
    return c;
  }

  Future<void> renameCategory(String id, String name) async {
    await _categories.rename(id, name);
    categories = await _categories.getAll();
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
  }

  Future<DeleteCategoryResult> deleteCategory(String id) async {
    final result = await _categories.deleteOrArchive(id);
    categories = await _categories.getAll();
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
    return result;
  }

  Future<String> exportCsv() async {
    final items = await _transactions.query(
      const TransactionFilter(sort: TxSort.date, ascending: true),
    );
    return _csv.exportCsv(items);
  }

  Future<CsvImportResult> importCsv(String content) async {
    final result = await _csv.importCsv(content);
    categories = await _categories.getAll();
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
    return result;
  }

  Future<String> createBackup() => _backup.createBackupJson();

  Future<void> restoreBackup(String json) async {
    await _backup.restoreBackupJson(json);
    await init();
    _persistSurvival();
  }

  Future<void> clearAllData() async {
    await _transactions.clearAll();
    final db = await _budgets.exportRows();
    if (db.isNotEmpty) {
      await _budgets.restore([]);
    }
    await refreshDashboard();
    await refreshTransactions();
    _persistSurvival();
  }

  BudgetStatus categoryBudgetStatus(String categoryId) {
    final budgetPaise = budget.categoryPaise[categoryId] ?? 0;
    final spent = categoryBreakdown
        .where((c) => c.categoryId == categoryId)
        .fold<int>(0, (s, c) => s + c.amountPaise);
    return BudgetStatus(budgetPaise: budgetPaise, spentPaise: spent);
  }

  double get averageDailyExpense {
    if (monthTotals.expensePaise == 0) return 0;
    final now = DateTime.now();
    final daysInMonth = DateKeys.endOfMonth(selectedMonth).day;
    final daysElapsed = DateKeys.isCurrentMonth(selectedMonth)
        ? now.day
        : daysInMonth;
    if (daysElapsed <= 0) return 0;
    return monthTotals.expensePaise / daysElapsed;
  }

  @override
  void dispose() {
    _survival.dispose();
    super.dispose();
  }
}
