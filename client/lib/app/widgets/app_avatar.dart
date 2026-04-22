import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.radius = 18});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
              .trim()
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.substring(0, 1).toUpperCase())
              .join();

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF0D82C0),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.65,
        ),
      ),
    );
  }
}
