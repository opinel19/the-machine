import 'package:flutter/material.dart';

import 'storage/settings.dart';

/// The Machine's colours, taken from the show's box designs.
abstract final class MachineColors {
  static const admin = Color(0xFFEEE93C);
  static const relevant = Color(0xFFEB1C24);
  static const irrelevant = Color(0xFFFFFFFF);
  static const catalyst = Color(0xFF116BF6);
  static const text = Color(0xFFEDEDED);
  static const dim = Color(0x8CFFFFFF);
  static const panel = Color(0xD9000000);
}

/// Samaritan's colours: white, black and one red.
abstract final class SamaritanColors {
  static const red = Color(0xFFFE0000);
  static const white = Color(0xFFFFFFFF);
  static const text = Color(0xFFF4F4F4);
  static const dim = Color(0x99FFFFFF);
  static const ink = Color(0xFF111111);
  static const paper = Color(0xFFF5F5F5);
  static const panel = Color(0xF2F5F5F5);
}

const String kMachineFont = 'ShareTechMono';
const String kSamaritanFont = 'Barlow';

TextStyle machineStyle({
  double size = 12,
  Color color = MachineColors.text,
  double spacing = 1.5,
  double height = 1.25,
}) => TextStyle(
  fontFamily: kMachineFont,
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  height: height,
);

/// Colours and type of one system's interface.
class ModeTheme {
  const ModeTheme._({
    required this.mode,
    required this.accent,
    required this.alert,
    required this.text,
    required this.dim,
    required this.panel,
    required this.panelText,
    required this.panelDim,
    required this.font,
    required this.spacing,
    this.weight,
  });

  static const machine = ModeTheme._(
    mode: MachineMode.machine,
    accent: MachineColors.admin,
    alert: MachineColors.relevant,
    text: MachineColors.text,
    dim: MachineColors.dim,
    panel: MachineColors.panel,
    panelText: MachineColors.text,
    panelDim: MachineColors.dim,
    font: kMachineFont,
    spacing: 1.5,
  );

  static const samaritan = ModeTheme._(
    mode: MachineMode.samaritan,
    accent: SamaritanColors.red,
    alert: SamaritanColors.red,
    text: SamaritanColors.text,
    dim: SamaritanColors.dim,
    panel: SamaritanColors.panel,
    panelText: SamaritanColors.ink,
    panelDim: Color(0x99111111),
    font: kSamaritanFont,
    spacing: 3,
    weight: FontWeight.w500,
  );

  static ModeTheme of(MachineMode mode) => mode == MachineMode.machine ? machine : samaritan;

  final MachineMode mode;

  /// Highlight colour: the Machine's yellow, Samaritan's red.
  final Color accent;
  final Color alert;
  final Color text;
  final Color dim;

  /// Sheets and banners, and the text on them.
  final Color panel;
  final Color panelText;
  final Color panelDim;
  final String font;
  final double spacing;
  final FontWeight? weight;

  bool get isSamaritan => mode == MachineMode.samaritan;

  TextStyle style({double size = 12, Color? color, double? spacing, FontWeight? weight, double height = 1.25}) =>
      TextStyle(
        fontFamily: font,
        fontSize: size,
        color: color ?? text,
        letterSpacing: spacing ?? this.spacing,
        fontWeight: weight ?? this.weight,
        height: height,
      );

  /// Text on [panel].
  TextStyle panelStyle({double size = 12, Color? color, double? spacing, FontWeight? weight}) =>
      style(size: size, color: color ?? panelText, spacing: spacing, weight: weight);
}

ThemeData machineTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    fontFamily: kMachineFont,
    colorScheme: const ColorScheme.dark(
      primary: MachineColors.admin,
      secondary: MachineColors.admin,
      surface: Colors.black,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MachineColors.admin,
      inactiveTrackColor: Color(0x33FFFFFF),
      thumbColor: MachineColors.admin,
      trackHeight: 2,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.black : MachineColors.dim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? MachineColors.admin : const Color(0x33FFFFFF),
      ),
    ),
  );
}

/// Material theming for sheets and dialogs in Samaritan mode.
ThemeData samaritanTheme() {
  return ThemeData(
    brightness: Brightness.light,
    fontFamily: kSamaritanFont,
    colorScheme: const ColorScheme.light(
      primary: SamaritanColors.red,
      secondary: SamaritanColors.red,
      surface: SamaritanColors.paper,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: SamaritanColors.red,
      inactiveTrackColor: Color(0x33111111),
      thumbColor: SamaritanColors.red,
      trackHeight: 2,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : const Color(0x99111111),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? SamaritanColors.red : const Color(0x22111111),
      ),
    ),
  );
}

extension SettingsTheme on MachineSettings {
  ModeTheme get theme => ModeTheme.of(mode);
}
