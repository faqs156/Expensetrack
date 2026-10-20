enum CategoryKind { expense, income }

class ExpenseCategory {
  final String id;
  final String name;
  final CategoryKind kind;
  final String iconKey;
  final int colorValue;
  final bool isDefault;
  final bool isArchived;
  final int sortOrder;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorValue,
    this.isDefault = false,
    this.isArchived = false,
    this.sortOrder = 0,
  });

  ExpenseCategory copyWith({
    String? id,
    String? name,
    CategoryKind? kind,
    String? iconKey,
    int? colorValue,
    bool? isDefault,
    bool? isArchived,
    int? sortOrder,
  }) {
    return ExpenseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'icon_key': iconKey,
        'color_value': colorValue,
        'is_default': isDefault ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory ExpenseCategory.fromMap(Map<String, Object?> map) {
    return ExpenseCategory(
      id: map['id'] as String,
      name: map['name'] as String,
      kind: CategoryKind.values.byName(map['kind'] as String),
      iconKey: map['icon_key'] as String,
      colorValue: map['color_value'] as int,
      isDefault: (map['is_default'] as int) == 1,
      isArchived: (map['is_archived'] as int) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
