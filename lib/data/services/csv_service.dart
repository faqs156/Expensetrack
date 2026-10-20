import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';
import '../models/transaction.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

class CsvImportResult {
  final int imported;
  final int skippedDuplicates;
  final int errors;
  final List<String> errorMessages;

  const CsvImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.errors,
    this.errorMessages = const [],
  });
}

class CsvService {
  CsvService({
    required TransactionRepository transactions,
    required CategoryRepository categories,
  }) : _tx = transactions,
       _cats = categories;

  final TransactionRepository _tx;
  final CategoryRepository _cats;

  static const headers = [
    'id',
    'date',
    'type',
    'amount',
    'category',
    'payment_method',
    'description',
  ];

  String exportCsv(List<Transaction> items) {
    final rows = <List<dynamic>>[headers];
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (final t in items) {
      rows.add([
        t.id,
        df.format(t.occurredAt),
        t.type.name,
        (t.amountPaise / 100).toStringAsFixed(2),
        t.categoryName ?? t.categoryId,
        t.paymentMethod.name,
        t.description ?? '',
      ]);
    }
    return const ListToCsvConverter().convert(rows);
  }

  Future<CsvImportResult> importCsv(String content) async {
    final rows = const CsvToListConverter(eol: '\n').convert(content.trim());
    if (rows.isEmpty) {
      return const CsvImportResult(
        imported: 0,
        skippedDuplicates: 0,
        errors: 1,
        errorMessages: ['Empty CSV file'],
      );
    }

    var start = 0;
    final header = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();
    if (header.contains('amount') && header.contains('type')) {
      start = 1;
    }

    final allCats = await _cats.getAll(includeArchived: true);
    var imported = 0;
    var skipped = 0;
    var errors = 0;
    final messages = <String>[];

    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.toString().trim().isEmpty)) continue;
      try {
        final map = _rowToMap(header, row, start == 1);
        final typeName = (map['type'] ?? '').toLowerCase();
        final type = typeName == 'income' ? TxType.income : TxType.expense;
        final amountStr = map['amount'] ?? '';
        final amount = double.tryParse(amountStr.replaceAll(',', ''));
        if (amount == null || amount <= 0) {
          throw FormatException('Invalid amount');
        }
        final amountPaise = (amount * 100).round();
        final catName = (map['category'] ?? '').trim();
        if (catName.isEmpty) throw FormatException('Missing category');

        ExpenseCategory? cat;
        for (final c in allCats) {
          final nameMatch = c.name.toLowerCase() == catName.toLowerCase();
          final kindMatch =
              (type == TxType.expense && c.kind == CategoryKind.expense) ||
              (type == TxType.income && c.kind == CategoryKind.income);
          if (nameMatch && kindMatch) {
            cat = c;
            break;
          }
        }
        cat ??= () {
          for (final c in allCats) {
            if (c.name.toLowerCase() == catName.toLowerCase()) return c;
          }
          return null;
        }();
        if (cat == null) {
          cat = await _cats.create(
            name: catName,
            kind: type == TxType.expense
                ? CategoryKind.expense
                : CategoryKind.income,
          );
          allCats.add(cat);
        }

        final dateRaw = map['date'] ?? '';
        final occurred = _parseDate(dateRaw);
        final pm = _parsePayment(map['payment_method'] ?? 'other');
        final desc = map['description'];
        final id = map['id']?.trim();
        final hashSource =
            '${id ?? ''}|$dateRaw|$typeName|$amountPaise|${cat.id}|${pm.name}|${desc ?? ''}';
        final hash = base64Url.encode(utf8.encode(hashSource));

        if (await _tx.importHashExists(hash)) {
          skipped++;
          continue;
        }
        if (id != null && id.isNotEmpty) {
          final existing = await _tx.getById(id);
          if (existing != null) {
            skipped++;
            continue;
          }
        }

        await _tx.insert(
          id: (id != null && id.isNotEmpty) ? id : null,
          amountPaise: amountPaise,
          type: type,
          categoryId: cat.id,
          occurredAt: occurred,
          paymentMethod: pm,
          description: desc,
          importHash: hash,
        );
        imported++;
      } catch (e) {
        errors++;
        if (messages.length < 8) {
          messages.add('Row ${i + 1}: $e');
        }
      }
    }

    return CsvImportResult(
      imported: imported,
      skippedDuplicates: skipped,
      errors: errors,
      errorMessages: messages,
    );
  }

  Map<String, String> _rowToMap(
    List<String> header,
    List<dynamic> row,
    bool hasHeader,
  ) {
    if (hasHeader) {
      final map = <String, String>{};
      for (var i = 0; i < header.length && i < row.length; i++) {
        map[header[i]] = row[i].toString();
      }
      return map;
    }
    return {
      'id': row.isNotEmpty ? row[0].toString() : '',
      'date': row.length > 1 ? row[1].toString() : '',
      'type': row.length > 2 ? row[2].toString() : 'expense',
      'amount': row.length > 3 ? row[3].toString() : '',
      'category': row.length > 4 ? row[4].toString() : '',
      'payment_method': row.length > 5 ? row[5].toString() : 'other',
      'description': row.length > 6 ? row[6].toString() : '',
    };
  }

  DateTime _parseDate(String raw) {
    final formats = [
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('dd-MM-yyyy'),
    ];
    for (final f in formats) {
      try {
        return f.parseStrict(raw.trim());
      } catch (_) {}
    }
    final iso = DateTime.tryParse(raw.trim());
    if (iso != null) return iso;
    throw FormatException('Invalid date "$raw"');
  }

  PaymentMethod _parsePayment(String raw) {
    final v = raw.trim().toLowerCase().replaceAll(' ', '_');
    return PaymentMethod.values.firstWhere(
      (e) => e.name == v,
      orElse: () => PaymentMethod.other,
    );
  }
}
