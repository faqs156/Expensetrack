import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/date_keys.dart';
import '../core/google_auth_config.dart';
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
import '../data/services/google_drive_sync_service.dart';
import '../data/services/vault_safety_service.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    CategoryRepository? categories,
    TransactionRepository? transactions,
    BudgetRepository? budgets,
    SettingsRepository? settings,
    CsvService? csv,
    BackupService? backup,
    DataSurvivalService? survival,
    VaultSafetyService? vaultSafety,
    GoogleDriveSyncService? driveSync,
  })  : _categories = categories ?? CategoryRepository(),
        _transactions = transactions ?? TransactionRepository(),
        _budgets = budgets ?? BudgetRepository(),
        _settingsRepo = settings ?? SettingsRepository(),
        _backup = backup ?? BackupService(),
        _survival = survival ?? DataSurvivalService(),
        _vaultSafety = vaultSafety ?? VaultSafetyService(),
        driveSync = driveSync ?? GoogleDriveSyncService() {
    _csv = csv ??
        CsvService(transactions: _transactions, categories: _categories);
    this.driveSync.addListener(_onDriveSyncChanged);
    this.driveSync.bindBackupBuilder(() => _backup.createBackupJson());
  }

  final VaultSafetyService _vaultSafety;

  GoogleSignInAccount? _prevDriveAccount;

  /// Allowlisted user: live Google session **or** resumed local session after refresh.
  /// (Web Google One Tap otherwise re-prompts on every reload.)
  bool get isAuthenticated =>
      GoogleAuthConfig.isConfigured &&
      GoogleAuthConfig.isEmailAllowed(driveSync.email);

  /// Shown once after a successful login (UI clears it).
  String? loginSuccessMessage;
  bool vaultLoaded = false;

  /// True when this browser needs Sync now to load Drive (common on Safari).
  bool needsCloudPull = false;

  void clearLoginSuccessMessage() {
    loginSuccessMessage = null;
    notifyListeners();
  }

  void _onDriveSyncChanged() {
    final current = driveSync.account;
    final becameSignedIn = _prevDriveAccount == null && current != null;
    _prevDriveAccount = current;
    notifyListeners();
    if (!becameSignedIn || !GoogleAuthConfig.isEmailAllowed(current.email)) {
      return;
    }
    // Sync now owns the flow when it reconnects Google — don't race it.
    if (driveSync.isManualSyncing) return;
    // Fresh login screen → full sync. Already in app → quiet background sync.
    if (!vaultLoaded) {
      unawaited(_afterGoogleSignIn());
    } else {
      unawaited(_quietBackgroundSync());
    }
  }

  Future<void> _afterGoogleSignIn() async {
    loading = true;
    notifyListeners();
    try {
      loginSuccessMessage = 'Signed in as ${driveSync.email}';
      notifyListeners();
      // User just tapped Google — interactive Drive grant is OK here.
      await _loadVaultAndSync(interactive: true);
      if (driveSync.lastError != null) {
        driveSync.clearLastError();
        await _loadVaultAndSync(interactive: false);
      }
      driveSync.clearLastError();
      needsCloudPull = false;
      _startPeriodicSync();
    } catch (e) {
      if (!vaultLoaded) {
        try {
          await _loadVaultFromDb();
        } catch (_) {}
      }
      loginSuccessMessage = 'Signed in as ${driveSync.email}';
      needsCloudPull = true;
      _startPeriodicSync();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _quietBackgroundSync() async {
    if (driveSync.status == DriveSyncStatus.syncing) return;
    try {
      await _loadVaultAndSync(interactive: false);
      needsCloudPull = false;
    } catch (_) {
      needsCloudPull = true;
    }
    notifyListeners();
  }

  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final BudgetRepository _budgets;
  final SettingsRepository _settingsRepo;
  late final CsvService _csv;
  final BackupService _backup;
  final DataSurvivalService _survival;
  final GoogleDriveSyncService driveSync;

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
    vaultLoaded = false;
    notifyListeners();
    try {
      WidgetsBinding.instance.addObserver(this);
      await driveSync.initialize();

      if (!GoogleAuthConfig.isConfigured) {
        error = 'Sign-in is unavailable right now. Try again later.';
        return;
      }

      // Local session and/or live Google — never show the vault to strangers.
      if (!isAuthenticated) {
        return;
      }

      // Fast path: show local data immediately (no Google wait / no banner flash).
      await _loadVaultFromDb();
      needsCloudPull = false;
      _startPeriodicSync();

      // Drive sync in background — does not block first paint.
      unawaited(_syncAfterOpenInBackground());
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncOnResume());
    }
  }

  Future<void> _syncOnResume() async {
    if (!isAuthenticated) return;
    await _syncAfterOpenInBackground();
  }

  Future<void> _syncAfterOpenInBackground() async {
    try {
      if (!driveSync.isSignedIn) {
        await driveSync.restoreGoogleSession(
          timeout: const Duration(seconds: 8),
          allowPrompt: false,
        );
      }
      if (driveSync.isSignedIn) {
        await _loadVaultAndSync(interactive: false);
        if (driveSync.hasPendingPush) {
          await driveSync.flushPendingPush(interactive: false, force: true);
        }
      } else if (driveSync.hasPendingPush) {
        // Still local-only — banner prompts Sync now.
        needsCloudPull = false;
      }
      final count = await _transactions.countAll();
      needsCloudPull = count == 0 && !driveSync.isSignedIn;
    } catch (_) {
      final count = await _transactions.countAll();
      needsCloudPull = count == 0;
    }
    notifyListeners();
  }

  Timer? _periodicSyncTimer;

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    final interval = driveSync.hasPendingPush
        ? GoogleAuthConfig.pendingPushRetryInterval
        : GoogleAuthConfig.periodicSyncInterval;
    _periodicSyncTimer = Timer.periodic(
      interval,
      (_) => unawaited(_periodicSyncTick()),
    );
  }

  Future<void> _periodicSyncTick() async {
    if (!isAuthenticated) return;
    if (driveSync.status == DriveSyncStatus.syncing) return;

    // Reconnect silently when possible so phone edits can reach Drive.
    if (!driveSync.isSignedIn) {
      await driveSync.restoreGoogleSession(
        timeout: const Duration(seconds: 5),
        allowPrompt: false,
      );
    }
    if (!driveSync.isSignedIn) {
      if (driveSync.hasPendingPush) notifyListeners();
      _startPeriodicSync(); // refresh interval if pending state changed
      return;
    }

    try {
      if (driveSync.hasPendingPush) {
        await driveSync.flushPendingPush(interactive: false, force: true);
      }
      final count = await _transactions.countAll();
      final safety = await _vaultSafety.readBest();
      final remoteJson = await driveSync.reconcile(
        buildBackupJson: _backup.createBackupJson,
        localTransactionCount: count,
        safetyJson: safety,
        interactive: false,
      );
      if (remoteJson != null) {
        await _safeRestore(remoteJson);
        settings = await _settingsRepo.load();
        categories = await _categories.getAll();
        await refreshDashboard();
        await refreshTransactions();
      }
      notifyListeners();
    } catch (_) {
      // Keep local vault; next Sync now / interval can retry.
    } finally {
      _startPeriodicSync();
    }
  }

  Future<void> _safeRestore(String json) async {
    final before = await _backup.createBackupJson();
    await _vaultSafety.save(VaultSafetyService.preRestoreId, before);
    await _backup.restoreBackupJson(json, mergeWithLocal: true);
    final after = await _backup.createBackupJson();
    await _vaultSafety.save(VaultSafetyService.latestId, after);
  }

  Future<void> _loadVaultFromDb() async {
    settings = await _settingsRepo.load();
    categories = await _categories.getAll();
    await refreshDashboard();
    await refreshTransactions();
    vaultLoaded = true;
  }

  Future<void> _loadVaultAndSync({required bool interactive}) async {
    await _loadVaultFromDb();

    var count = await _transactions.countAll();
    if (count == 0 && !restoreOfferDismissed) {
      final surviving = await _survival.readSurvivingBackup();
      if (surviving != null && surviving.trim().isNotEmpty) {
        pendingRestoreJson = surviving;
      }
    }

    if (!driveSync.isSignedIn) {
      needsCloudPull = true;
      return;
    }

    final safety = await _vaultSafety.readBest();
    final remoteJson = await driveSync.reconcile(
      buildBackupJson: _backup.createBackupJson,
      localTransactionCount: count,
      safetyJson: safety,
      interactive: interactive,
    );
    if (remoteJson != null) {
      await _safeRestore(remoteJson);
      await _loadVaultFromDb();
      count = await _transactions.countAll();
    }

    if (count > 0) {
      final snap = await _backup.createBackupJson();
      await _vaultSafety.save(VaultSafetyService.latestId, snap);
      _persistSurvival();
    }
    needsCloudPull = false;
    vaultLoaded = true;
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
    // Full vault JSON: categories, transactions, budgets, settings → Drive.
    unawaited(() async {
      try {
        final json = await _backup.createBackupJson();
        await _vaultSafety.save(VaultSafetyService.latestId, json);
      } catch (_) {}
    }());
    _survival.scheduleAfterChange(() => _backup.createBackupJson());
    driveSync.schedulePush(() => _backup.createBackupJson());
  }

  Future<void> signInWithGoogle() async {
    await driveSync.signInInteractive();
    // Drive reconcile runs via _onDriveSyncChanged → _afterGoogleSignIn.
  }

  Future<void> signOutGoogle() async {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;

    // Must reconnect + upload BEFORE clearing Google — local-only session
    // was the main reason Mac never saw phone edits.
    try {
      final json = await _backup.createBackupJson();
      await _vaultSafety.save(VaultSafetyService.preSignOutId, json);
      if (!driveSync.isSignedIn) {
        await driveSync.ensureGoogleConnected(
          timeout: const Duration(seconds: 45),
        );
      }
      await driveSync.pushBackup(json, interactive: true);
      await driveSync.verifyRemoteContains(json, interactive: true);
    } catch (_) {
      // Still sign out; local SQLite + safety snapshot remain for next login.
    }

    await driveSync.signOut();
    vaultLoaded = false;
    loginSuccessMessage = null;
    // Clear UI only — IndexedDB/SQLite transactions stay on this device.
    categories = [];
    recent = [];
    filteredTransactions = [];
    monthTotals = const MonthTotals(expensePaise: 0, incomePaise: 0);
    notifyListeners();
  }

  Future<void> syncGoogleDriveNow() async {
    final count = await _transactions.countAll();
    final safety = await _vaultSafety.readBest();
    await driveSync.syncNow(
      buildBackupJson: _backup.createBackupJson,
      restoreBackup: (json) async {
        await _safeRestore(json);
      },
      localTransactionCount: count,
      safetyJson: safety,
    );
    // Confirm the shared account vault includes local transactions.
    final localJson = await _backup.createBackupJson();
    await driveSync.verifyRemoteContains(localJson, interactive: true);
    await refreshDashboard();
    await refreshTransactions();
    final after = await _transactions.countAll();
    needsCloudPull = after == 0 && !driveSync.isSignedIn;
    _startPeriodicSync();
    notifyListeners();
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
    await _safeRestore(json);
    settings = await _settingsRepo.load();
    categories = await _categories.getAll();
    await refreshDashboard();
    await refreshTransactions();
    notifyListeners();
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
    WidgetsBinding.instance.removeObserver(this);
    _periodicSyncTimer?.cancel();
    driveSync.removeListener(_onDriveSyncChanged);
    driveSync.dispose();
    _survival.dispose();
    super.dispose();
  }
}
