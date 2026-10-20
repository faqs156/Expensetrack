import 'package:flutter/material.dart';

import '../../data/seed/default_categories.dart';

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.iconKey,
    required this.colorValue,
    this.size = 40,
  });

  final String iconKey;
  final int colorValue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(iconForKey(iconKey), color: color, size: size * 0.48),
    );
  }
}
