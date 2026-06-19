import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../services/settings_service.dart';

class CloudProfileSelector extends StatelessWidget {
  const CloudProfileSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final profiles = settings.selectableProfiles;
    if (profiles.isEmpty) {
      return SizedBox(
        width: 220,
        child: InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.cloud_off_outlined),
          ),
          child: Text(
            '未启用云服务',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String>(
        key: ValueKey(settings.activeProfile?.id),
        initialValue: settings.activeProfile?.id,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.cloud_queue_outlined),
          labelText: '默认云服务',
        ),
        items: [
          for (final profile in profiles)
            DropdownMenuItem(
              value: profile.id,
              child: Text(
                '${profile.provider.label} · ${profile.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) async {
          if (id == null) return;
          settings.setActiveProfile(id);
          await context.read<SettingsService>().save();
        },
      ),
    );
  }
}
