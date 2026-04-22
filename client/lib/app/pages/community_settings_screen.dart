import 'package:flutter/material.dart';

class CommunitySettingsScreen extends StatefulWidget {
  const CommunitySettingsScreen({super.key});

  @override
  State<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  bool _allowInvites = true;
  bool _requireApproval = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: _allowInvites,
            onChanged: (value) => setState(() => _allowInvites = value),
            title: const Text('Allow member invites'),
          ),
          SwitchListTile(
            value: _requireApproval,
            onChanged: (value) => setState(() => _requireApproval = value),
            title: const Text('Require approval for new posts'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {},
            child: const Text('Save community preferences'),
          ),
        ],
      ),
    );
  }
}
