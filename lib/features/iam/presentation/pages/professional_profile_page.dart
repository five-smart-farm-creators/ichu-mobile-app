import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/public_shell.dart';
import '../../../../shared/application/services/language_service.dart';
import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../application/services/professional_profile_service.dart';
import '../widgets/auth_failure_notice.dart';

/// Displays the signed-in user's professional profile without editing it.
final class ProfessionalProfilePage extends StatefulWidget {
  const ProfessionalProfilePage({
    super.key,
    required this.language,
    required this.profileService,
    required this.onBack,
  });

  final LanguageService language;
  final ProfessionalProfileService profileService;
  final VoidCallback onBack;

  @override
  State<ProfessionalProfilePage> createState() =>
      _ProfessionalProfilePageState();
}

final class _ProfessionalProfilePageState
    extends State<ProfessionalProfilePage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.profileService.load());
  }

  @override
  void didUpdateWidget(covariant ProfessionalProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileService != widget.profileService) {
      unawaited(widget.profileService.load());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.profileService,
    builder: (context, _) {
      final service = widget.profileService;
      final strings = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final isReady =
          service.status == ProfessionalProfileStatus.ready &&
          service.canView &&
          service.account != null;

      return PublicShell(
        language: widget.language,
        showBackButton: true,
        onBack: widget.onBack,
        backLabel: strings.iamProfileBack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                strings.iamProfessionalProfile,
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 12),
            Text(strings.iamProfileLead),
            const SizedBox(height: 20),
            if (service.busy) ...[
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(strings.iamProfileLoading)),
                  ],
                ),
              ),
            ] else if (service.status == ProfessionalProfileStatus.idle) ...[
              Semantics(
                liveRegion: true,
                child: Text(strings.iamProfileReadOnly),
              ),
            ] else if (isReady) ...[
              _EmailSummary(email: service.account!.email),
              const SizedBox(height: 16),
              Text(
                strings.iamProfileReadOnly,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (service.profile case final profile?)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileValue(
                          label: strings.iamProfileSpecialty,
                          value: profile.specialty,
                        ),
                        const SizedBox(height: 18),
                        _ProfileValue(
                          label: strings.iamProfileLicense,
                          value: profile.licenseNumber,
                        ),
                        const SizedBox(height: 18),
                        _ProfileValue(
                          label: strings.iamProfileExperience,
                          value: profile.yearsOfExperience.toString(),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(strings.iamProfileNoProfile),
                  ),
                ),
            ] else ...[
              if (service.error != null)
                AuthFailureNotice(failure: service.error!)
              else
                Semantics(
                  liveRegion: true,
                  child: Text(strings.iamProfileNoProfile),
                ),
            ],
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: OutlinedButton.icon(
                key: const Key('profile-reload'),
                onPressed: !service.busy && service.canReload
                    ? () => unawaited(service.load())
                    : null,
                icon: const Icon(Icons.refresh),
                label: Text(strings.iamProfileReload),
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _EmailSummary extends StatelessWidget {
  const _EmailSummary({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.account_circle_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(email, softWrap: true)),
        ],
      ),
    ),
  );
}

final class _ProfileValue extends StatelessWidget {
  const _ProfileValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}
