enum TxType { expense, income }

enum PaymentMethod { cash, upi, card, bank, other }

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.upi => 'UPI',
    PaymentMethod.card => 'Card',
    PaymentMethod.bank => 'Bank Transfer',
    PaymentMethod.other => 'Other',
  };
}

class Transaction {
  final String id;
  final int amountPaise;
  final TxType type;
  final String categoryId;
  final DateTime occurredAt;
  final PaymentMethod paymentMethod;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? importHash;

  /// Joined fields (optional).
  final String? categoryName;
  final String? categoryIconKey;
  final int? categoryColor;

  const Transaction({
    required this.id,
    required this.amountPaise,
    required this.type,
    required this.categoryId,
    required this.occurredAt,
    required this.paymentMethod,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.importHash,
    this.categoryName,
    this.categoryIconKey,
    this.categoryColor,
  });

  Transaction copyWith({
    String? id,
    int? amountPaise,
    TxType? type,
    String? categoryId,
    DateTime? occurredAt,
    PaymentMethod? paymentMethod,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? importHash,
    String? categoryName,
    String? categoryIconKey,
    int? categoryColor,
  }) {
    return Transaction(
      id: id ?? this.id,
      amountPaise: amountPaise ?? this.amountPaise,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      occurredAt: occurredAt ?? this.occurredAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      importHash: importHash ?? this.importHash,
      categoryName: categoryName ?? this.categoryName,
      categoryIconKey: categoryIconKey ?? this.categoryIconKey,
      categoryColor: categoryColor ?? this.categoryColor,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'amount_paise': amountPaise,
    'type': type.name,
    'category_id': categoryId,
    'occurred_at': occurredAt.millisecondsSinceEpoch,
    'payment_method': paymentMethod.name,
    'description': description,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'import_hash': importHash,
  };

  factory Transaction.fromMap(Map<String, Object?> map) {
    return Transaction(
      id: map['id'] as String,
      amountPaise: map['amount_paise'] as int,
      type: TxType.values.byName(map['type'] as String),
      categoryId: map['category_id'] as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        map['occurred_at'] as int,
      ),
      paymentMethod: PaymentMethod.values.byName(
        map['payment_method'] as String,
      ),
      description: map['description'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      importHash: map['import_hash'] as String?,
      categoryName: map['category_name'] as String?,
      categoryIconKey: map['category_icon_key'] as String?,
      categoryColor: map['category_color'] as int?,
    );
  }
}
