import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_config.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validation.dart';
import '../../models/commands.dart';
import '../../models/connection_state.dart';
import '../../models/settings.dart';
import '../../models/vehicle_kind.dart';
import '../../services/haptics.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_modal.dart';
import '../../widgets/app_slider.dart';
import '../connection/connection_controller.dart';
import '../demo/demo_mode_sheet.dart';
import 'settings_category.dart';
import 'settings_controller.dart';
import 'widgets/category_bar.dart';
import 'widgets/motor_calibration_panel.dart';
import 'widgets/servo_calibration_panel.dart';
import 'widgets/settings_tile.dart';

/// App and vehicle configuration.
///
/// Long enough that finding anything by scrolling is a chore, so the seven
/// groups get a pinned selector: tap to jump, and it tracks where you are as
/// you scroll past.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ScrollController _scrollController = ScrollController();

  /// One gate for every haptic on this screen, so the setting is honoured in
  /// a single place rather than repeated at each row.
  void _tick() =>
      Haptics.selection(enabled: ref.read(settingsProvider).hapticsEnabled);
  final Map<SettingsCategory, GlobalKey> _sectionKeys = {
    for (final category in SettingsCategory.values) category: GlobalKey(),
  };

  SettingsCategory _active = SettingsCategory.vehicle;

  /// Set while a tap-driven scroll is animating, so the scroll listener does
  /// not fight the selection the user just made by re-deriving it from the
  /// sections flying past.
  bool _isJumping = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncActiveWithScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncActiveWithScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll offset at which [category]'s heading sits just below the pinned
  /// bar, or null if it is not laid out yet (off-screen in a lazy list).
  double? _offsetOf(SettingsCategory category) {
    final context = _sectionKeys[category]?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;

    final viewport = RenderAbstractViewport.of(box);
    return viewport.getOffsetToReveal(box, 0).offset - CategoryBar.height;
  }

  void _syncActiveWithScroll() {
    if (_isJumping || !_scrollController.hasClients) return;

    final position = _scrollController.offset;
    // A section counts as "current" once its heading reaches the bar, with a
    // little slack so the switch happens as it arrives rather than after it
    // has already scrolled past.
    const slack = AppSpacing.xxl;

    var current = SettingsCategory.values.first;
    for (final category in SettingsCategory.values) {
      final offset = _offsetOf(category);
      if (offset == null) continue;
      if (offset - slack <= position) current = category;
    }

    // A final section shorter than the viewport (likely for APP on a tablet)
    // can never scroll its heading up to the bar, so the heading rule alone
    // leaves the previous chip lit at the bottom of the list. Reaching the
    // end of the scroll extent counts as selecting the last section.
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (position >= maxExtent - 1) {
      for (final category in SettingsCategory.values.reversed) {
        if (_offsetOf(category) != null) {
          current = category;
          break;
        }
      }
    }

    if (current != _active) setState(() => _active = current);
  }

  Future<void> _jumpTo(SettingsCategory category) async {
    final offset = _offsetOf(category);
    if (offset == null || !_scrollController.hasClients) return;

    setState(() {
      _active = category;
      _isJumping = true;
    });

    await _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: AppDurations.slow,
      curve: AppDurations.standard,
    );

    if (mounted) setState(() => _isJumping = false);
  }

  /// Motors/Sensors/Lights are OP0148 car calibration — the spiderbot has
  /// none of that hardware, so both the section list and the category chips
  /// hide them rather than showing panels with nothing to calibrate.
  static const _spiderCategories = [
    SettingsCategory.vehicle,
    SettingsCategory.controls,
    SettingsCategory.connection,
    SettingsCategory.app,
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final link = ref.watch(connectionProvider);
    final controller = ref.read(settingsProvider.notifier);
    final isCar = settings.vehicleKind == VehicleKind.car;
    final categories = isCar ? SettingsCategory.values : _spiderCategories;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('SETTINGS', style: AppTypography.labelStrong),
      ),
      body: SafeArea(
        top: false,
        child: PageConstraints(
          maxWidth: 820,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: CategoryBarDelegate(
                  active: _active,
                  onSelected: _jumpTo,
                  categories: categories,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.huge,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _section(
                      SettingsCategory.vehicle,
                      _vehicleSection(settings, controller),
                    ),
                    _section(
                      SettingsCategory.controls,
                      _controlsSection(settings, controller),
                    ),
                    if (isCar) ...[
                      _section(
                        SettingsCategory.motors,
                        _motorsSection(settings, link.isConnected),
                      ),
                      _section(
                        SettingsCategory.sensors,
                        _sensorsSection(settings, controller),
                      ),
                      _section(
                        SettingsCategory.lights,
                        _lightsSection(settings, controller),
                      ),
                    ],
                    _section(
                      SettingsCategory.connection,
                      _connectionSection(settings, controller, link),
                    ),
                    _section(
                      SettingsCategory.app,
                      _appSection(settings, controller),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(SettingsCategory category, Widget child) =>
      KeyedSubtree(key: _sectionKeys[category], child: child);

  // --- Sections -------------------------------------------------------------

  Widget _vehicleSection(AppSettings settings, SettingsController controller) {
    return SettingsSection(
      title: SettingsCategory.vehicle.label,
      icon: SettingsCategory.vehicle.icon,
      children: [
        SettingsRow(
          label: 'Vehicle type',
          description: settings.vehicleKind == VehicleKind.car
              ? 'ESP32 4WD car, differential drive'
              : 'Arduino Nano quadruped, gait-based walking',
          icon: settings.vehicleKind == VehicleKind.car
              ? Icons.directions_car_rounded
              : Icons.bug_report_rounded,
          trailing: AppBadge(
            label: settings.vehicleKind.label.toUpperCase(),
            level: StatusLevel.neutral,
            showIcon: false,
            size: AppBadgeSize.small,
          ),
          onTap: () {
            _tick();
            final next = settings.vehicleKind == VehicleKind.car
                ? VehicleKind.spider
                : VehicleKind.car;
            controller.update(
              (s) => s.copyWith(
                vehicleKind: next,
                vehicleName: next.defaultVehicleName,
              ),
            );
          },
        ),
        SettingsRow(
          label: 'Vehicle name',
          description: settings.vehicleName,
          icon: Icons.badge_outlined,
          onTap: () => _editVehicleName(settings),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: AppSlider(
            label: 'MAXIMUM SPEED',
            leadingIcon: Icons.speed_rounded,
            value: settings.maxSpeedPercent.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            unit: '%',
            helperText: 'Caps every drive command the app sends.',
            onChanged: (value) => controller.update(
              (s) => s.copyWith(maxSpeedPercent: value.round()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlsSection(AppSettings settings, SettingsController controller) {
    final isCar = settings.vehicleKind == VehicleKind.car;

    return SettingsSection(
      title: SettingsCategory.controls.label,
      icon: SettingsCategory.controls.icon,
      children: [
        // Joystick side/sensitivity/ramping only mean something for the
        // car's analog differential drive — the spiderbot's direction pad
        // has nothing continuous to tune.
        if (isCar) ...[
          SettingsRow(
            label: 'Joystick side',
            description: settings.joystickSide.description,
            icon: Icons.swap_horiz_rounded,
            trailing: AppBadge(
              label: settings.joystickSide.label,
              level: StatusLevel.neutral,
              showIcon: false,
              size: AppBadgeSize.small,
            ),
            onTap: () {
              _tick();
              controller.update(
                (s) => s.copyWith(joystickSide: s.joystickSide.opposite),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSlider(
                  label: 'JOYSTICK SENSITIVITY',
                  leadingIcon: Icons.tune_rounded,
                  value: settings.joystickSensitivity,
                  min: SettingsRange.minSensitivity,
                  max: SettingsRange.maxSensitivity,
                  divisions: 15,
                  valueFormatter: (v) => '${v.toStringAsFixed(1)}×',
                  helperText:
                      'Higher values respond more aggressively off-centre.',
                  onChanged: (value) => controller.update(
                    (s) => s.copyWith(joystickSensitivity: value),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSlider(
                  label: 'DEAD ZONE',
                  leadingIcon: Icons.adjust_rounded,
                  value: settings.deadZonePercent.toDouble(),
                  min: SettingsRange.minDeadZonePercent.toDouble(),
                  max: SettingsRange.maxDeadZonePercent.toDouble(),
                  divisions: 40,
                  unit: '%',
                  helperText: 'Stick travel near centre treated as neutral.',
                  onChanged: (value) => controller.update(
                    (s) => s.copyWith(deadZonePercent: value.round()),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSlider(
                  label: 'ACCELERATION',
                  leadingIcon: Icons.trending_up_rounded,
                  value: settings.accelerationRate,
                  min: SettingsRange.minRamp,
                  max: SettingsRange.maxRamp,
                  divisions: 19,
                  unit: '%/s',
                  helperText:
                      'How quickly output rises toward the stick position.',
                  onChanged: (value) => controller.update(
                    (s) => s.copyWith(accelerationRate: value),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSlider(
                  label: 'DECELERATION',
                  leadingIcon: Icons.trending_down_rounded,
                  value: settings.decelerationRate,
                  min: SettingsRange.minRamp,
                  max: SettingsRange.maxRamp,
                  divisions: 19,
                  unit: '%/s',
                  helperText: 'How quickly output falls when easing off.',
                  onChanged: (value) => controller.update(
                    (s) => s.copyWith(decelerationRate: value),
                  ),
                ),
              ],
            ),
          ),
        ],
        SettingsSwitchRow(
          label: 'Haptic feedback',
          description: isCar
              ? 'Vibrate on joystick engagement and direction changes'
              : 'Vibrate on direction-pad presses',
          icon: Icons.vibration_rounded,
          value: settings.hapticsEnabled,
          onChanged: (value) {
            if (value) Haptics.selection(enabled: true);
            controller.update((s) => s.copyWith(hapticsEnabled: value));
          },
        ),
      ],
    );
  }

  Widget _motorsSection(AppSettings settings, bool isConnected) {
    return SettingsSection(
      title: SettingsCategory.motors.label,
      icon: SettingsCategory.motors.icon,
      subtitle: 'Direction and trim, sent to the vehicle on release',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: MotorCalibrationPanel(
            settings: settings,
            isConnected: isConnected,
          ),
        ),
      ],
    );
  }

  Widget _sensorsSection(AppSettings settings, SettingsController controller) {
    final thresholds = Validators.distanceThresholds(
      cautionCm: settings.cautionDistanceCm,
      dangerCm: settings.dangerDistanceCm,
    );

    return SettingsSection(
      title: SettingsCategory.sensors.label,
      icon: SettingsCategory.sensors.icon,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSlider(
                label: 'MINIMUM OBSTACLE DISTANCE',
                leadingIcon: Icons.front_hand_rounded,
                value: settings.minObstacleDistanceCm.toDouble(),
                min: SettingsRange.minDistanceCm.toDouble(),
                max: SettingsRange.maxDistanceCm.toDouble(),
                divisions: 39,
                unit: 'cm',
                color: AppColors.info,
                helperText: 'Closest the vehicle will approach while avoiding.',
                onChanged: (value) => controller.update(
                  (s) => s.copyWith(minObstacleDistanceCm: value.round()),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSlider(
                label: 'CAUTION THRESHOLD',
                leadingIcon: Icons.warning_amber_rounded,
                value: settings.cautionDistanceCm.toDouble(),
                min: SettingsRange.minDistanceCm.toDouble(),
                max: SettingsRange.maxDistanceCm.toDouble(),
                divisions: 39,
                unit: 'cm',
                color: AppColors.caution,
                onChanged: (value) => controller.update(
                  (s) => s.copyWith(cautionDistanceCm: value.round()),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSlider(
                label: 'DANGER THRESHOLD',
                leadingIcon: Icons.dangerous_rounded,
                value: settings.dangerDistanceCm.toDouble(),
                min: SettingsRange.minDistanceCm.toDouble(),
                max: SettingsRange.maxDistanceCm.toDouble(),
                divisions: 39,
                unit: 'cm',
                color: AppColors.danger,
                onChanged: (value) => controller.update(
                  (s) => s.copyWith(dangerDistanceCm: value.round()),
                ),
              ),
              if (!thresholds.isValid) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: AppColors.caution,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${thresholds.error!} — corrected automatically when '
                        'saved.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.caution,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              ServoCalibrationPanel(settings: settings),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lightsSection(AppSettings settings, SettingsController controller) {
    return SettingsSection(
      title: SettingsCategory.lights.label,
      icon: SettingsCategory.lights.icon,
      children: [
        SettingsRow(
          label: 'Default state',
          description: 'Headlight mode when the vehicle connects',
          icon: Icons.power_settings_new_rounded,
          trailing: AppBadge(
            label: settings.defaultLightMode.label,
            level: StatusLevel.neutral,
            showIcon: false,
            size: AppBadgeSize.small,
          ),
          onTap: () {
            _tick();
            controller.update(
              (s) => s.copyWith(
                defaultLightMode:
                    LightMode.values[(s.defaultLightMode.index + 1) %
                        LightMode.values.length],
              ),
            );
          },
        ),
        SettingsRow(
          label: 'Flash speed',
          description: 'Rate the vehicle blinks in a flash mode',
          icon: Icons.flash_on_rounded,
          trailing: AppBadge(
            label: settings.flashSpeed.label,
            level: StatusLevel.neutral,
            showIcon: false,
            size: AppBadgeSize.small,
          ),
          onTap: () {
            _tick();
            controller.update(
              (s) => s.copyWith(
                flashSpeed: s.flashSpeed == FlashSpeed.slow
                    ? FlashSpeed.fast
                    : FlashSpeed.slow,
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: AppSlider(
            label: 'BRIGHTNESS',
            leadingIcon: Icons.brightness_6_rounded,
            value: settings.lightBrightness.toDouble(),
            min: SettingsRange.minBrightness.toDouble(),
            max: SettingsRange.maxBrightness.toDouble(),
            divisions: 18,
            unit: '%',
            helperText: 'Requires PWM-capable headlight wiring on the vehicle.',
            onChanged: (value) => controller.update(
              (s) => s.copyWith(lightBrightness: value.round()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _connectionSection(
    AppSettings settings,
    SettingsController controller,
    LinkState link,
  ) {
    return SettingsSection(
      title: SettingsCategory.connection.label,
      icon: SettingsCategory.connection.icon,
      children: [
        SettingsSwitchRow(
          label: 'Auto reconnect',
          description: 'Retry the saved vehicle with backoff after a dropout',
          icon: Icons.autorenew_rounded,
          value: settings.autoReconnect,
          onChanged: (value) {
            _tick();
            controller.update((s) => s.copyWith(autoReconnect: value));
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: AppSlider(
            label: 'WATCHDOG TIMEOUT',
            leadingIcon: Icons.timer_outlined,
            value: settings.commandTimeoutMs.toDouble(),
            min: AppConfig.minCommandTimeoutMs.toDouble(),
            max: AppConfig.maxCommandTimeoutMs.toDouble(),
            divisions: 17,
            unit: 'ms',
            helperText:
                'Vehicle stops on its own if no drive command arrives within '
                'this window. Sent to the vehicle on connect.',
            onChanged: (value) => controller.update(
              (s) => s.copyWith(commandTimeoutMs: value.round()),
            ),
          ),
        ),
        SettingsRow(
          label: 'Last vehicle',
          description: link.hasRememberedDevice
              ? link.displayName
              : 'No vehicle saved on this phone',
          icon: Icons.memory_rounded,
        ),
        if (link.hasRememberedDevice)
          SettingsRow(
            label: 'Forget vehicle',
            description: 'Clear the saved device and start from a fresh scan',
            icon: Icons.delete_outline_rounded,
            isDestructive: true,
            onTap: _forgetVehicle,
          ),
      ],
    );
  }

  Widget _appSection(AppSettings settings, SettingsController controller) {
    return SettingsSection(
      title: SettingsCategory.app.label,
      icon: SettingsCategory.app.icon,
      children: [
        SettingsSwitchRow(
          label: 'Mock mode',
          description:
              'Drive a simulated vehicle. No Bluetooth commands are sent.',
          icon: Icons.science_rounded,
          value: settings.mockMode,
          onChanged: _setMockMode,
        ),
        if (settings.mockMode)
          SettingsRow(
            label: 'Simulator controls',
            description:
                'Set the battery, place an obstacle, inject faults into the '
                'mock vehicle',
            icon: Icons.tune_rounded,
            onTap: () => DemoModeSheet.show(context),
          ),
        SettingsRow(
          label: 'Units',
          description: 'Distance readouts use ${settings.units.shortLabel}',
          icon: Icons.straighten_rounded,
          trailing: AppBadge(
            label: settings.units.label,
            level: StatusLevel.neutral,
            showIcon: false,
            size: AppBadgeSize.small,
          ),
          onTap: () {
            _tick();
            controller.update(
              (s) => s.copyWith(
                units: s.units == DistanceUnits.metric
                    ? DistanceUnits.imperial
                    : DistanceUnits.metric,
              ),
            );
          },
        ),
        SettingsRow(
          label: 'Replay setup guide',
          description: 'Walk through mode, permissions and safety again',
          icon: Icons.restart_alt_rounded,
          onTap: () => context.push(AppRoute.onboarding),
        ),
        SettingsRow(
          label: 'Reset to defaults',
          description: 'Restore every setting to its factory value',
          icon: Icons.restore_rounded,
          isDestructive: true,
          onTap: _resetSettings,
        ),
      ],
    );
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _setMockMode(bool enabled) async {
    final link = ref.read(connectionProvider);
    if (link.isConnected) {
      final confirmed = await AppModal.confirm(
        context,
        title: 'Disconnect vehicle?',
        message: enabled
            ? 'Switching to mock mode disconnects ${link.displayName}.'
            : 'Leaving mock mode disconnects the simulated vehicle.',
        confirmLabel: 'SWITCH',
        icon: Icons.swap_horiz_rounded,
      );
      if (!confirmed) return;
      await ref.read(connectionProvider.notifier).disconnect();
    }
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(mockMode: enabled));
  }

  Future<void> _forgetVehicle() async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'Forget this vehicle?',
      message:
          'ROVEROS will stop reconnecting automatically and you will need to '
          'scan for the vehicle again.',
      confirmLabel: 'FORGET',
      confirmVariant: AppButtonVariant.danger,
      level: StatusLevel.danger,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await ref.read(connectionProvider.notifier).forgetDevice();
  }

  Future<void> _resetSettings() async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'Reset all settings?',
      message:
          'Speed limits, calibration and connection preferences return to their '
          'defaults. The saved vehicle is kept.',
      confirmLabel: 'RESET',
      confirmVariant: AppButtonVariant.danger,
      level: StatusLevel.danger,
      icon: Icons.restore_rounded,
    );
    if (!confirmed) return;
    ref.read(settingsProvider.notifier).resetToDefaults();
  }

  Future<void> _editVehicleName(AppSettings settings) async {
    final textController = TextEditingController(text: settings.vehicleName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vehicle name'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: SettingsRange.maxVehicleNameLength,
          style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'ESP32-CAR',
            counterStyle: TextStyle(color: AppColors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (name == null) return;
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(vehicleName: name));
  }
}
