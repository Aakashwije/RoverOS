import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';
import '../settings_category.dart';

/// Sticky category selector for the settings list.
///
/// Settings is long enough that the scrollbar stops being a useful map of it.
/// This turns the list into something you can jump around: the chips say what
/// is in here, and the highlighted one says where you are.
class CategoryBar extends StatefulWidget {
  const CategoryBar({
    super.key,
    required this.active,
    required this.onSelected,
    this.categories = SettingsCategory.values,
  });

  final SettingsCategory active;
  final ValueChanged<SettingsCategory> onSelected;

  /// Which chips to show. Defaults to every category; the active vehicle kind
  /// may hide the ones it has no settings for (e.g. Motors/Sensors/Lights for
  /// the spiderbot) so there is never a chip that scrolls to nothing.
  final List<SettingsCategory> categories;

  /// Fixed height, so the pinned sliver header does not resize while scrolling
  /// and the scroll-target maths can subtract a constant.
  static const double height = 54;

  @override
  State<CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<CategoryBar> {
  final ScrollController _controller = ScrollController();
  late Map<SettingsCategory, GlobalKey> _chipKeys = {
    for (final category in widget.categories) category: GlobalKey(),
  };

  @override
  void didUpdateWidget(covariant CategoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categories != oldWidget.categories) {
      _chipKeys = {
        for (final category in widget.categories) category: GlobalKey(),
      };
    }
    if (widget.active != oldWidget.active) _revealActive();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolling the list past a section should bring its chip into view too —
  /// otherwise the bar shows a selection the user cannot see.
  ///
  /// Drives the horizontal controller directly rather than calling
  /// [Scrollable.ensureVisible], which reveals the target in *every* enclosing
  /// scrollable — including the settings list this bar is pinned to, which is
  /// the one thing that must not move as a side effect of tracking it.
  void _revealActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;

      final chipContext = _chipKeys[widget.active]?.currentContext;
      final box = chipContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;

      final position = _controller.position;
      final target = RenderAbstractViewport.of(
        box,
      ).getOffsetToReveal(box, 0.5).offset;

      _controller.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: AppDurations.normal,
        curve: AppDurations.standard,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CategoryBar.height,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: [
          for (final category in widget.categories) ...[
            _CategoryChip(
              key: _chipKeys[category],
              category: category,
              isActive: category == widget.active,
              onTap: () => widget.onSelected(category),
            ),
            if (category != widget.categories.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.category,
    required this.isActive,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accent : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isActive,
      label: '${category.label} settings',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppDurations.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : AppColors.surfaceElevated,
              borderRadius: AppRadii.pillRadius,
              border: Border.all(
                color: isActive ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  category.label,
                  style: AppTypography.label.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pins [CategoryBar] under the app bar as the list scrolls.
class CategoryBarDelegate extends SliverPersistentHeaderDelegate {
  const CategoryBarDelegate({
    required this.active,
    required this.onSelected,
    this.categories = SettingsCategory.values,
  });

  final SettingsCategory active;
  final ValueChanged<SettingsCategory> onSelected;
  final List<SettingsCategory> categories;

  @override
  double get minExtent => CategoryBar.height;

  @override
  double get maxExtent => CategoryBar.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return CategoryBar(
      active: active,
      onSelected: onSelected,
      categories: categories,
    );
  }

  @override
  bool shouldRebuild(CategoryBarDelegate oldDelegate) =>
      oldDelegate.active != active ||
      oldDelegate.onSelected != onSelected ||
      oldDelegate.categories != categories;
}
