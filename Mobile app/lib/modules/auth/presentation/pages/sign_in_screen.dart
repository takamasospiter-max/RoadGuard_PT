import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:roadguard_ai/core/services/auth_service.dart';

import '../../routes/auth_paths.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_layout.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _identity = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .authenticate(email: _identity.text, password: _password.text);
      _password.clear();
      if (mounted) continueAfterAuthentication(context, ref);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to sign in. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: AuthLayout(
      pageTitle: 'Log in',
      title: 'Welcome back',
      subtitle: 'Sign in and make the journey yours.',
      children: [
        if (_error != null) AuthError(_error!),
        AutofillGroup(
          child: Column(
            children: [
              AuthField(
                label: 'Email address',
                hint: 'you@example.com',
                controller: _identity,
                fieldKey: const Key('sign-in-identity'),
                keyboardType: TextInputType.emailAddress,
                icon: Icons.mail_outline_rounded,
                autofillHints: const [AutofillHints.username],
                validator: emailValidator,
              ),
              AuthField(
                label: 'Password',
                hint: 'Enter your password',
                controller: _password,
                fieldKey: const Key('sign-in-password'),
                password: true,
                icon: Icons.lock_outline_rounded,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: _signIn,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter your password.' : null,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy
                ? null
                : () => showAccountUnavailable(
                    context,
                    title: 'Password recovery',
                    message: 'Email password recovery is not available yet. No reset message has been sent. You can continue exploring as a guest.',
                  ),
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('sign-in-submit'),
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Log in'),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('New to RoadGuard?'),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => context.pushReplacement(AuthPaths.register),
              child: const Text('Create account'),
            ),
          ],
        ),
      ],
    ),
  );
}
