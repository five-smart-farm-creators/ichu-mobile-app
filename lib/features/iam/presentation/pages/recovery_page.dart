import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/auth_service.dart';
import '../../domain/model/auth_failure.dart';
import '../../domain/services/credential_rules.dart';
import '../widgets/auth_failure_notice.dart';

final class RecoveryPage extends StatefulWidget {
  const RecoveryPage({
    super.key,
    required this.language,
    required this.authentication,
    required this.onBack,
  });

  final LanguageService language;
  final AuthService authentication;
  final VoidCallback onBack;

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

final class _RecoveryPageState extends State<RecoveryPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  bool _attempted = false;
  bool _submitting = false;
  bool _sent = false;

  Future<void> _submit() async {
    if (_submitting ||
        !widget.authentication.canRecover ||
        widget.authentication.busy) {
      return;
    }
    setState(() => _attempted = true);
    if (!_form.currentState!.validate()) {
      _emailFocus.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _emailFocus.context != null) {
        await Scrollable.ensureVisible(_emailFocus.context!, alignment: 0.1);
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _sent = false;
    });
    final sent = await widget.authentication.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _sent = sent;
    });
    if (sent) _email.clear();
  }

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.authentication,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final auth = widget.authentication;
      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.iamBackToSignIn,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.iamRecoveryTitle,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.iamRecoveryLead),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  autovalidateMode: _attempted && !_sent
                      ? AutovalidateMode.always
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('recovery-email'),
                        controller: _email,
                        focusNode: _emailFocus,
                        maxLength: 254,
                        enabled: !_submitting,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.send,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: strings.iamEmail,
                          errorMaxLines: 4,
                          counterText: '',
                        ),
                        validator: (value) =>
                            CredentialRules.validEmail(value ?? '')
                            ? null
                            : strings.iamEmailInvalid,
                        onChanged: (_) {
                          if (_sent) setState(() => _sent = false);
                          auth.clearError();
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(strings.iamRecoveryNote),
                      if (_submitting)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(strings.iamRecoverySending),
                          ),
                        ),
                      if (!auth.canRecover)
                        const AuthFailureNotice(
                          failure: AuthFailure(AuthFailureCode.configuration),
                        )
                      else if (auth.error != null)
                        AuthFailureNotice(failure: auth.error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('recovery-submit'),
                        onPressed: auth.canRecover && !auth.busy && !_submitting
                            ? _submit
                            : null,
                        child: Text(
                          _submitting
                              ? strings.iamRecoverySending
                              : strings.iamRecoverySubmit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_sent) ...[
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.iamRecoveryResultTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(strings.iamRecoveryResultBody),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onBack,
              child: Text(strings.iamBackToSignIn),
            ),
          ],
        ),
      );
    },
  );
}
