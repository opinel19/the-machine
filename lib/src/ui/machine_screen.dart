import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../machine/subject.dart';
import '../storage/identity_store.dart';
import '../storage/settings.dart';
import 'admin_sheet.dart';
import 'alert_flash.dart';
import 'boot_sequence.dart';
import 'camera_feed.dart';
import 'capture.dart';
import 'crash_overlay.dart';
import 'designation_menu.dart';
import 'enhance.dart';
import 'enrollment_view.dart';
import 'hud.dart';
import 'machine_overlay.dart';
import 'map_view.dart';
import 'message_banner.dart';
import 'number_view.dart';
import 'pixel_transition.dart';
import 'settings_sheet.dart';
import 'number_history_sheet.dart';
import 'simulation_view.dart';
import 'subject_database_sheet.dart';
import 'talk_view.dart';
import 'verification_view.dart';

class MachineScreen extends StatefulWidget {
  const MachineScreen({super.key});

  @override
  State<MachineScreen> createState() => _MachineScreenState();
}

class _MachineScreenState extends State<MachineScreen> with WidgetsBindingObserver {
  final _identities = IdentityStore();
  final _settings = MachineSettings();
  late final _controller = MachineController(identities: _identities, settings: _settings);
  final _enhance = EnhanceState();
  final _overlayBoundary = GlobalKey();
  bool _flash = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.start().then((_) => _runLaunchAction());
  }

  /// Carries out what a Siri shortcut, app shortcut or widget asked for.
  Future<void> _runLaunchAction() async {
    final action = await _controller.native.takeLaunchAction();
    if (!mounted || action == null) return;
    // Let the boot sequence and camera settle first.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    switch (action) {
      case 'talk':
        await _talk(listen: true);
      case 'number':
        await _controller.issueNumber();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _identities.dispose();
    _settings.dispose();
    _enhance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _controller.pause();
      case AppLifecycleState.resumed:
        _controller.resume();
        _runLaunchAction();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Runs [action] once an admin is verified (when the admin lock is on).
  Future<void> _asAdmin(Future<void> Function() action) async {
    if (_controller.enrollment != null) return;
    if (await _controller.verifyAdmin() && mounted) await action();
  }

  Future<void> _onAdmin() => _asAdmin(() async {
    if (_identities.admins.isEmpty) {
      await enrollNewAdmin(context, _controller);
    } else {
      await showAdminSheet(context, _controller);
    }
  });

  Future<void> _onSettings() => _asAdmin(
    () => showSettingsSheet(
      context,
      _controller,
      onManageAdmins: () => showAdminSheet(context, _controller),
      onSubjectDatabase: () => showSubjectDatabase(context, _controller),
      onNumberHistory: () => showNumberHistory(context, _controller),
      onTalk: _talk,
      onMap: () => showSurveillanceMap(context, _controller),
    ),
  );

  /// Opens the conversation; asking what will happen runs a simulation on
  /// whoever is most interesting in view.
  Future<void> _talk({bool listen = false}) => showTalk(
    context,
    _controller,
    listen: listen,
    onSimulate: () => _simulate(_controller.simulationTarget()),
  );

  Future<void> _simulate(Subject? subject) => showSimulation(context, _controller, subject: subject);

  Future<void> _onDesignate(Subject subject) async {
    final designation = await pickDesignation(
      context,
      settings: _settings,
      subjectLabel: subject.code,
      current: subject.identity?.designation == Designation.admin ? null : subject.identity?.designation,
      onSimulate: () => _simulate(subject),
    );
    if (designation != null) await _controller.designate(subject.id, designation);
  }

  Future<void> _onCapture() async {
    if (_capturing) return;
    final boundary = _overlayBoundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    _capturing = true;
    HapticFeedback.mediumImpact();
    setState(() => _flash = true);
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _flash = false);
    });
    try {
      final png = await composeCapture(
        controller: _controller,
        enhance: _enhance,
        overlay: boundary,
        view: MediaQuery.sizeOf(context),
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      if (png != null) await _controller.saveCapture(png);
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            CameraFeed(controller: _controller, enhance: _enhance),
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: FeedTexturePainter(
                    scanlines: _settings.mode == MachineMode.machine && _settings.machineVision,
                  ),
                ),
              ),
            ),
            RepaintBoundary(
              key: _overlayBoundary,
              child: MachineOverlay(
                controller: _controller,
                enhance: _enhance,
                onDesignate: _onDesignate,
                onSimulate: _simulate,
              ),
            ),
            PixelTransition(controller: _controller),
            EnhanceOverlay(controller: _controller, enhance: _enhance),
            AlertFlash(alerts: _controller.alerts),
            MachineHud(
              controller: _controller,
              onAdmin: _onAdmin,
              onSettings: _onSettings,
              onCapture: _onCapture,
              onTalk: _talk,
            ),
            NumberView(controller: _controller),
            EnrollmentView(controller: _controller),
            VerificationView(controller: _controller),
            MessageBanner(messages: _controller.messages, settings: _settings),
            if (_flash) const IgnorePointer(child: ColoredBox(color: Color(0xCCFFFFFF))),
            CrashOverlay(crashes: _controller.crashes, settings: _settings),
            BootSequence(controller: _controller),
          ],
        ),
      ),
    );
  }
}
