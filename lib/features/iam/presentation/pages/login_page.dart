import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../core/theme/ichu_colors.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/auth_service.dart';
import '../../domain/model/auth_failure.dart';
import '../../domain/services/credential_rules.dart';
import '../widgets/auth_failure_notice.dart';
import '../widgets/auth_hero.dart';

/// Credentials remain in disposable form controllers, never application state.
final class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.language,
    required this.authentication,
    required this.onRecover,
    required this.onOpenTerms,
  });

  final LanguageService language;
  final AuthService authentication;
  final VoidCallback onRecover;
  final VoidCallback onOpenTerms;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

final class _LoginPageState extends State<LoginPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _passwordVisible = false;
  bool _submitting = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _clearPassword();
    }
  }

  void _clearPassword() {
    _password.clear();
    if (_passwordVisible && mounted) setState(() => _passwordVisible = false);
  }

  void _leaveFor(VoidCallback navigate) {
    _clearPassword();
    TextInput.finishAutofillContext(shouldSave: false);
    FocusScope.of(context).unfocus();
    navigate();
  }

  Future<void> _submit() async {
    if (_submitting ||
        widget.authentication.busy ||
        !widget.authentication.canSignIn) {
      return;
    }
    setState(() => _attempted = true);
    if (!_form.currentState!.validate()) {
      final focus = CredentialRules.validEmail(_email.text)
          ? _passwordFocus
          : _emailFocus;
      focus.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && focus.context != null) {
        await Scrollable.ensureVisible(focus.context!, alignment: 0.1);
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    var success = false;
    try {
      success = await widget.authentication.signIn(_email.text, _password.text);
    } finally {
      TextInput.finishAutofillContext(shouldSave: success);
      if (mounted) {
        _clearPassword();
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _email.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.authentication,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final auth = widget.authentication;
      final busy = auth.busy || _submitting;
      final available = auth.canSignIn && !busy;
      final progressMessage = switch (auth.status) {
        SessionStatus.signingIn => strings.iamSigningIn,
        SessionStatus.signingOut => strings.iamSigningOut,
        _ => strings.iamChecking,
      };
      return PublicShell(
        language: widget.language,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHero(),
            const SizedBox(height: 24),
            Text(
              strings.iamSignInMode,
              style: theme.textTheme.labelLarge!.copyWith(
                color: IchuColors.accentText,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                strings.welcomeTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.welcomeLead),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Form(
                    key: _form,
                    autovalidateMode: _attempted
                        ? AutovalidateMode.always
                        : AutovalidateMode.disabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('login-email'),
                          controller: _email,
                          focusNode: _emailFocus,
                          maxLength: 120,
                          enabled: !busy,
                          keyboardType: TextInputType.emailAddress,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _passwordFocus.requestFocus(),
                          decoration: InputDecoration(
                            labelText: strings.iamEmail,
                            errorMaxLines: 4,
                            counterText: '',
                          ),
                          onChanged: (_) => auth.clearError(),
                          validator: (value) =>
                              CredentialRules.validEmail(value ?? '')
                              ? null
                              : strings.iamEmailInvalid,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('login-password'),
                          controller: _password,
                          maxLength: 128,
                          focusNode: _passwordFocus,
                          enabled: !busy,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: !_passwordVisible,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          onChanged: (_) => auth.clearError(),
                          decoration: InputDecoration(
                            labelText: strings.iamPassword,
                            errorMaxLines: 4,
                            counterText: '',
                            suffixIcon: IconButton(
                              tooltip: _passwordVisible
                                  ? strings.iamHidePassword
                                  : strings.iamShowPassword,
                              onPressed: busy
                                  ? null
                                  : () => setState(
                                      () =>
                                          _passwordVisible = !_passwordVisible,
                                    ),
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              CredentialRules.validPassword(value ?? '')
                              ? null
                              : strings.iamPasswordInvalid,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _leaveFor(widget.onRecover),
                          child: Text(strings.iamForgotPassword),
                        ),
                        if (!auth.canSignIn && !busy)
                          const AuthFailureNotice(
                            failure: AuthFailure(AuthFailureCode.configuration),
                          )
                        else if (auth.error != null)
                          AuthFailureNotice(failure: auth.error!),
                        if (busy)
                          Semantics(
                            liveRegion: true,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(progressMessage),
                            ),
                          ),
                        FilledButton(
                          key: const Key('login-submit'),
                          onPressed: available ? _submit : null,
                          child: Text(
                            _submitting
                                ? strings.iamSigningIn
                                : strings.iamSignIn,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(strings.iamSignInNote, style: theme.textTheme.bodySmall),
            if (auth.error?.code == AuthFailureCode.signOutFailed)
              TextButton(
                onPressed: busy ? null : () => auth.signOut(),
                child: Text(strings.iamSignOut),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _leaveFor(widget.onOpenTerms),
              child: Text(strings.termsTitle),
            ),
          ],
        ),
      );
    },
  );
}
