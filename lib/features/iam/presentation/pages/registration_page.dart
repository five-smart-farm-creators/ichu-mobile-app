import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../core/theme/ichu_colors.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/registration_service.dart';
import '../../domain/model/auth_failure.dart';
import '../../domain/model/iam_account.dart';
import '../../domain/model/registration_details.dart';
import '../../domain/services/credential_rules.dart';
import '../widgets/auth_failure_notice.dart';
import '../widgets/registration_details_section.dart';

final class RegistrationPage extends StatefulWidget {
  const RegistrationPage({
    super.key,
    required this.language,
    required this.registration,
    required this.onBack,
    required this.onOpenTerms,
  });

  final LanguageService language;
  final RegistrationService registration;
  final VoidCallback onBack;
  final VoidCallback onOpenTerms;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

final class _RegistrationPageState extends State<RegistrationPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _ranchName = TextEditingController();
  final _region = TextEditingController();
  final _district = TextEditingController();
  final _headCount = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  AccountRole? _role;
  bool _resume = false;
  bool _visible = false;
  bool _attempted = false;
  bool _submitting = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.registration.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _clearPasswords();
    }
  }

  void _clearPasswords() {
    _password.clear();
    _confirmation.clear();
    if (_visible && mounted) setState(() => _visible = false);
  }

  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    _clearPasswords();
    TextInput.finishAutofillContext(shouldSave: false);
    await widget.registration.cancel();
    if (mounted) widget.onBack();
  }

  void _terms() {
    _clearPasswords();
    TextInput.finishAutofillContext(shouldSave: false);
    FocusScope.of(context).unfocus();
    widget.onOpenTerms();
  }

  RegistrationDetails? _details() {
    final role = _role;
    if (role == null) return null;
    return RegistrationDetails(
      role: role,
      ranch: role == AccountRole.ranchManager
          ? RanchRegistration(
              name: _ranchName.text,
              region: _region.text,
              district: _district.text,
              estimatedHeadCount: int.tryParse(_headCount.text) ?? -1,
            )
          : null,
    );
  }

  Future<bool> _validate() async {
    setState(() => _attempted = true);
    final invalidFields = _form.currentState?.validateGranularly();
    if (invalidFields != null && invalidFields.isEmpty) return true;
    FocusScope.of(context).unfocus();
    await WidgetsBinding.instance.endOfFrame;
    final remainingFields = invalidFields?.where((field) => field.mounted);
    if (mounted && remainingFields != null && remainingFields.isNotEmpty) {
      await Scrollable.ensureVisible(
        remainingFields.first.context,
        alignment: 0.1,
      );
    }
    return false;
  }

  Future<void> _submitIdentity() async {
    final service = widget.registration;
    if (_submitting ||
        service.busy ||
        service.requiresSignOut ||
        !(_resume ? service.canResume : service.canRegister)) {
      return;
    }
    if (!await _validate() || !mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      if (_resume) {
        await service.resume(_email.text, _password.text);
      } else {
        await service.register(_email.text, _password.text);
      }
    } finally {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) {
        _clearPasswords();
        setState(() {
          _submitting = false;
          _attempted = false;
        });
      }
    }
  }

  Future<void> _complete() async {
    final service = widget.registration;
    if (_submitting ||
        service.busy ||
        service.requiresSignOut ||
        !service.canRegister) {
      return;
    }
    if (service.needsReconciliation) {
      await service.reconcile();
      return;
    }
    if (!await _validate() || !mounted) return;
    final details = _details();
    if (details != null && details.isValid) await service.complete(details);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in [
      _email,
      _password,
      _confirmation,
      _ranchName,
      _region,
      _district,
      _headCount,
    ]) {
      controller.dispose();
    }
    for (final focus in [_emailFocus, _passwordFocus, _confirmationFocus]) {
      focus.dispose();
    }
    super.dispose();
  }

  Widget _detailsFields(bool enabled) => RegistrationDetailsSection(
    role: _role,
    onRoleChanged: (role) => setState(() => _role = role),
    name: _ranchName,
    region: _region,
    district: _district,
    headCount: _headCount,
    enabled: enabled,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && !_leaving) unawaited(widget.registration.cancel());
    },
    child: ListenableBuilder(
      listenable: widget.registration,
      builder: (context, _) {
        final service = widget.registration;
        final strings = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final busy = service.busy || _submitting;
        final completed = service.status == RegistrationStatus.completed;
        final pending = !completed && service.user != null;
        final progress = switch (service.status) {
          RegistrationStatus.completing => strings.iamRegistrationCompleting,
          RegistrationStatus.cancelling => strings.iamRegistrationCancellation,
          _ => strings.iamRegistrationCreating,
        };
        return PublicShell(
          language: widget.language,
          showBackButton: true,
          onBack: _back,
          backLabel: strings.iamBackToSignIn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  completed
                      ? strings.iamRegistrationSuccessTitle
                      : pending
                      ? strings.iamRegistrationPendingTitle
                      : strings.iamRegistrationTitle,
                  style: theme.textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: completed,
                child: Text(
                  completed
                      ? strings.iamRegistrationSuccessBody
                      : pending
                      ? strings.iamRegistrationPendingBody
                      : strings.iamRegistrationLead,
                ),
              ),
              const SizedBox(height: 20),
              if (completed) ...[
                FilledButton(
                  key: const Key('registration-sign-in'),
                  onPressed: _back,
                  child: Text(strings.iamBackToSignIn),
                ),
              ] else
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
                            if (pending) ...[
                              Text(service.user!.email),
                              const SizedBox(height: 16),
                              if (service.verificationSent)
                                Semantics(
                                  liveRegion: true,
                                  child: Text(strings.iamRegistrationSent),
                                ),
                              const SizedBox(height: 16),
                              if (service.needsReconciliation)
                                Text(strings.iamRegistrationUncertain)
                              else
                                _detailsFields(
                                  !busy && !service.requiresSignOut,
                                ),
                            ] else ...[
                              TextFormField(
                                key: const Key('registration-email'),
                                controller: _email,
                                focusNode: _emailFocus,
                                enabled: !busy,
                                maxLength: 254,
                                keyboardType: TextInputType.emailAddress,
                                textCapitalization: TextCapitalization.none,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                                onChanged: (_) => service.clearError(),
                                decoration: InputDecoration(
                                  labelText: strings.iamEmail,
                                  counterText: '',
                                  errorMaxLines: 4,
                                ),
                                validator: (value) =>
                                    CredentialRules.validEmail(value ?? '')
                                    ? null
                                    : strings.iamEmailInvalid,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                key: const Key('registration-password'),
                                controller: _password,
                                focusNode: _passwordFocus,
                                enabled: !busy,
                                maxLength: 128,
                                keyboardType: TextInputType.visiblePassword,
                                obscureText: !_visible,
                                autocorrect: false,
                                enableSuggestions: false,
                                enableIMEPersonalizedLearning: false,
                                smartDashesType: SmartDashesType.disabled,
                                smartQuotesType: SmartQuotesType.disabled,
                                autofillHints: [
                                  _resume
                                      ? AutofillHints.password
                                      : AutofillHints.newPassword,
                                ],
                                textInputAction: _resume
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                onFieldSubmitted: (_) {
                                  if (_resume) {
                                    unawaited(_submitIdentity());
                                  } else {
                                    _confirmationFocus.requestFocus();
                                  }
                                },
                                decoration: InputDecoration(
                                  labelText: strings.iamPassword,
                                  counterText: '',
                                  errorMaxLines: 4,
                                  suffixIcon: IconButton(
                                    tooltip: _visible
                                        ? strings.iamHidePassword
                                        : strings.iamShowPassword,
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                            () => _visible = !_visible,
                                          ),
                                    icon: Icon(
                                      _visible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    (_resume
                                        ? CredentialRules.validSignInPassword(
                                            value ?? '',
                                          )
                                        : CredentialRules.validPassword(
                                            value ?? '',
                                          ))
                                    ? null
                                    : _resume
                                    ? strings.iamSignInPasswordInvalid
                                    : strings.iamPasswordInvalid,
                              ),
                              if (!_resume) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  key: const Key('registration-confirmation'),
                                  controller: _confirmation,
                                  focusNode: _confirmationFocus,
                                  enabled: !busy,
                                  maxLength: 128,
                                  keyboardType: TextInputType.visiblePassword,
                                  obscureText: !_visible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  enableIMEPersonalizedLearning: false,
                                  smartDashesType: SmartDashesType.disabled,
                                  smartQuotesType: SmartQuotesType.disabled,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submitIdentity(),
                                  decoration: InputDecoration(
                                    labelText: strings.iamConfirmPassword,
                                    counterText: '',
                                    errorMaxLines: 4,
                                  ),
                                  validator: (value) =>
                                      value == _password.text &&
                                          (value ?? '').isNotEmpty
                                      ? null
                                      : strings.iamConfirmPasswordInvalid,
                                ),
                              ],
                            ],
                            if (service.error?.code ==
                                AuthFailureCode.emailNotVerified)
                              Semantics(
                                liveRegion: true,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    strings.iamRegistrationNotVerified,
                                    style: const TextStyle(
                                      color: IchuColors.danger,
                                    ),
                                  ),
                                ),
                              )
                            else if (service.error != null)
                              AuthFailureNotice(failure: service.error!),
                            if (!service.canRegister &&
                                !busy &&
                                service.error == null)
                              const AuthFailureNotice(
                                failure: AuthFailure(
                                  AuthFailureCode.configuration,
                                ),
                              ),
                            if (busy)
                              Semantics(
                                liveRegion: true,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(progress),
                                ),
                              ),
                            const SizedBox(height: 16),
                            if (service.requiresSignOut)
                              FilledButton(
                                key: const Key('registration-cleanup'),
                                onPressed: busy ? null : () => service.cancel(),
                                child: Text(strings.iamSignOut),
                              )
                            else if (pending) ...[
                              FilledButton(
                                key: const Key('registration-complete'),
                                onPressed: service.canRegister && !busy
                                    ? _complete
                                    : null,
                                child: Text(
                                  service.needsReconciliation
                                      ? strings.iamRegistrationReconcile
                                      : strings.iamRegistrationComplete,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                key: const Key('registration-resend'),
                                onPressed: busy
                                    ? null
                                    : () => service.resendVerification(),
                                child: Text(strings.iamRegistrationResend),
                              ),
                            ] else ...[
                              FilledButton(
                                key: const Key('registration-submit'),
                                onPressed:
                                    !busy &&
                                        (_resume
                                            ? service.canResume
                                            : service.canRegister)
                                    ? _submitIdentity
                                    : null,
                                child: Text(
                                  _resume
                                      ? strings.iamRegistrationResumeSubmit
                                      : strings.iamRegistrationSubmit,
                                ),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () {
                                        _clearPasswords();
                                        setState(() {
                                          _resume = !_resume;
                                          _attempted = false;
                                        });
                                      },
                                child: Text(
                                  _resume
                                      ? strings.iamRegistrationNew
                                      : strings.iamRegistrationResume,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                strings.iamRegistrationPrivacy,
                style: theme.textTheme.bodySmall,
              ),
              TextButton(onPressed: _terms, child: Text(strings.termsTitle)),
              TextButton(
                onPressed: _back,
                child: Text(
                  pending || busy
                      ? strings.iamRegistrationCancel
                      : strings.iamBackToSignIn,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
