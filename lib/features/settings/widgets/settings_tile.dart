import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/section_header.dart';

/// A titled group of settings rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, icon: icon, subtitle: subtitle),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Divider(),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

/// Row with a label, optional description and a trailing control.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    this.trailing,
    this.onTap,
    this.icon,
    this.isDestructive = false,
  });

  final String label;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.danger : AppColors.textPrimary;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: isDestructive ? color : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.body.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: AppTypography.bodySmall.copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ] else if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Settings row whose control is a switch. Tapping anywhere toggles it.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.icon,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: description == null ? label : '$label. $description',
      child: ExcludeSemantics(
        child: SettingsRow(
          label: label,
          description: description,
          icon: icon,
          onTap: () => onChanged(!value),
          trailing: Switch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
