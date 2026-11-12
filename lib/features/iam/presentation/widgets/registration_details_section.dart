import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/infrastructure/i18n/generated/app_localizations.dart';
import '../../domain/model/iam_account.dart';

/// Only the two self-registration roles implemented by the backend are offered.
final class RegistrationDetailsSection extends StatelessWidget {
  const RegistrationDetailsSection({
    super.key,
    required this.role,
    required this.onRoleChanged,
    required this.name,
    required this.region,
    required this.district,
    required this.headCount,
    required this.enabled,
  });

  final AccountRole? role;
  final ValueChanged<AccountRole?> onRoleChanged;
  final TextEditingController name;
  final TextEditingController region;
  final TextEditingController district;
  final TextEditingController headCount;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<AccountRole>(
          key: ValueKey(role),
          initialValue: role,
          isExpanded: true,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: strings.iamRegistrationRole,
            errorMaxLines: 4,
          ),
          items: [
            DropdownMenuItem(
              value: AccountRole.veterinarian,
              child: Text(strings.iamRoleVeterinarian),
            ),
            DropdownMenuItem(
              value: AccountRole.ranchManager,
              child: Text(strings.iamRoleManager),
            ),
          ],
          onChanged: enabled ? onRoleChanged : null,
          validator: (value) =>
              value == null ? strings.iamRegistrationRoleRequired : null,
        ),
        const SizedBox(height: 12),
        Text(strings.iamRegistrationRoleNote),
        if (role == AccountRole.ranchManager) ...[
          const SizedBox(height: 16),
          Text(strings.iamRegistrationRanchNote),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('registration-ranch-name'),
            controller: name,
            enabled: enabled,
            maxLength: 160,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.iamRegistrationRanchName,
              counterText: '',
              errorMaxLines: 4,
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty || value!.trim().length > 160
                ? strings.iamRegistrationNameInvalid
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('registration-region'),
            controller: region,
            enabled: enabled,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.iamRegistrationRegion,
              counterText: '',
              errorMaxLines: 4,
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty || value!.trim().length > 120
                ? strings.iamRegistrationLocationInvalid
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('registration-district'),
            controller: district,
            enabled: enabled,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.iamRegistrationDistrict,
              counterText: '',
              errorMaxLines: 4,
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty || value!.trim().length > 120
                ? strings.iamRegistrationLocationInvalid
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('registration-head-count'),
            controller: headCount,
            enabled: enabled,
            maxLength: 10,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: strings.iamRegistrationHeadCount,
              counterText: '',
              errorMaxLines: 4,
            ),
            validator: (value) {
              final count = int.tryParse(value ?? '');
              return count == null || count < 0 || count > 2147483647
                  ? strings.iamRegistrationCountInvalid
                  : null;
            },
          ),
        ],
      ],
    );
  }
}
