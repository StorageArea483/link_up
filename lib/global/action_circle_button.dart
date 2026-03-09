import 'package:flutter/material.dart';
import 'package:link_up/styles/styles.dart';

class ActionCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const ActionCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        height: 44,
        width: 44,
        decoration: const BoxDecoration(
          color: AppColors.iconBackground,
          shape: BoxShape.circle,
        ),
        child: Center(child: Icon(icon, color: AppColors.linkBlue)),
      ),
    );
  }
}
