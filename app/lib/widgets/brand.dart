import 'package:flutter/material.dart';

import '../core/theme.dart';

class CholoLogo extends StatelessWidget {
  const CholoLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: CholoColors.green, borderRadius: BorderRadius.circular(size * 0.3)),
          child: Icon(Icons.navigation_rounded, color: CholoColors.sun, size: size * 0.6),
        ),
        SizedBox(width: size * 0.3),
        Text(
          'Cholo',
          style: TextStyle(fontSize: size * 0.75, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
      ],
    );
  }
}
