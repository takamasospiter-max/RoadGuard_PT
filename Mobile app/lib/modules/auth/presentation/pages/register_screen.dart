import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';

import '../../routes/auth_paths.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_layout.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .authenticate(
            name: _name.text,
            email: _email.text,
            password: _password.text,
          );
      _password.clear();
      _confirmation.clear();
      if (mounted) continueAfterAuthentication(context, ref);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to create your account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: AuthLayout(
      pageTitle: 'Create account',
      title: 'Create Account',
      subtitle: 'Your next journey starts here.',
      children: [
        if (_error != null) AuthError(_error!),
        AutofillGroup(
          child: Column(
            children: [
              AuthField(
                label: 'Full name',
                hint: 'Enter your name',
                controller: _name,
                fieldKey: const Key('register-name'),
                keyboardType: TextInputType.name,
                icon: Icons.person_outline,
                autofillHints: const [AutofillHints.name],
                validator: (v) =>
                    v == null || v.trim().isEmpty || v.trim().length > 160
                    ? 'Enter your name (up to 160 characters).'
                    : null,
              ),
              AuthField(
                label: 'Email address',
                hint: 'you@example.com',
                controller: _email,
                fieldKey: const Key('register-email'),
                keyboardType: TextInputType.emailAddress,
                icon: Icons.mail_outline,
                autofillHints: const [AutofillHints.email],
                validator: emailValidator,
              ),
              AuthField(
                label: 'Password',
                hint: 'At least 12 characters',
                controller: _password,
                fieldKey: const Key('register-password'),
                password: true,
                icon: Icons.lock_outline,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v == null || v.length < 12
                    ? 'Use at least 12 characters.'
                    : null,
              ),
              AuthField(
                label: 'Confirm password',
                hint: 'Enter your password again',
                controller: _confirmation,
                fieldKey: const Key('register-confirmation'),
                password: true,
                icon: Icons.lock_outline,
                textInputAction: TextInputAction.done,
                onSubmitted: _register,
                validator: (v) => v == null || v.isEmpty || v != _password.text
                    ? 'Passwords do not match.'
                    : null,
              ),
            ],
          ),
        ),
        Text(
          'Use a unique password. Avoid your name, email and common passwords.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Your name and email create your traveler account. Location and road-sensor access are separate choices.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('register-submit'),
          onPressed: _busy ? null : _register,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Already have an account?'),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => context.pushReplacement(AuthPaths.signIn),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    ),
  );
}
