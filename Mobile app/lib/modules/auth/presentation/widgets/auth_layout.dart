import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/modules/boarding/routes/boarding_paths.dart';
import 'package:roadguard_ai/modules/auth/routes/auth_paths.dart';
import 'package:roadguard_ai/modules/home/routes/home_paths.dart';
import 'package:roadguard_ai/modules/profile/presentation/providers/settings_provider.dart';

void continueAfterAuthentication(BuildContext context, WidgetRef ref) {
  context.go(
    ref.read(settingsProvider).onboardingComplete
        ? HomePaths.explore
        : BoardingPaths.permissions,
  );
}

Future<void> showAccountUnavailable(
  BuildContext context, {
  String title = 'Account services are not connected',
  String message =
      'Sign-in and registration are not available in this local preview. '
      'Nothing has been sent or saved.',
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Got it'),
      ),
    ],
  ),
);

class AuthLayout extends ConsumerWidget {
  const AuthLayout({
    super.key,
    required this.pageTitle,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String pageTitle;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  // The auth screens are designed light only (fixed light background below).
  // Force the light theme here, so that with the phone in dark mode the
  // theme-coloured parts (page title, text buttons like "Forgot password?"
  // and "Create account", input fields) don't get dark-theme colours: near-white
  // text on this light background. Everything below reads the theme through the
  // LayoutBuilder's context, which sits inside this Theme.
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Theme(data: roadTheme(Brightness.light), child: _scaffold(ref));

  Widget _scaffold(WidgetRef ref) => Scaffold(
    backgroundColor: const Color(0xFFF6F9FA),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 460,
                minHeight: constraints.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFFEDF3F4),
                          child: IconButton(
                            tooltip: 'Back',
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: RoadColors.deepBlue,
                            ),
                            onPressed: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go(
                                  ref.read(settingsProvider).onboardingComplete
                                      ? AuthPaths.signIn
                                      : BoardingPaths.permissions,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            pageTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'RoadGuard AI',
                          style: TextStyle(
                            color: RoadColors.authBrand,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: RoadColors.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: RoadColors.muted,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (!ref.watch(authServiceProvider).configured) ...[
                      Container(
                        key: const Key('auth-note'),
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: RoadColors.authNoteBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Account connection is not configured. Connect the RoadGuard API to sign in.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: RoadColors.authNoteInk,
                          ),
                        ),
                      ),
                    ],
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.hint,
    this.keyboardType,
    this.password = false,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
    this.icon,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final String? hint;
  final TextInputType? keyboardType;
  final bool password;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final Iterable<String>? autofillHints;
  final IconData? icon;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: RoadColors.ink,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          obscureText: widget.password && _obscured,
          enableSuggestions: !widget.password,
          autocorrect: false,
          autofillHints: widget.autofillHints,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: widget.validator,
          scrollPadding: const EdgeInsets.all(32),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.icon == null
                ? null
                : Icon(widget.icon, size: 20),
            errorMaxLines: 3,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: RoadColors.authFieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: RoadColors.blue, width: 1.6),
            ),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
}

String? requiredExample(String? value) =>
    value == null || value.trim().isEmpty ? 'Enter an example value.' : null;

String? emailValidator(String? value) =>
    value == null ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
    ? 'Enter a valid email address.'
    : null;

class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('auth-error'),
        margin: const EdgeInsets.only(bottom: 10),
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: RoadColors.authError,
          ),
        ),
      ),
    );
  }
}
