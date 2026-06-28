import 'package:flutter/material.dart';

void showAppAboutSheet(BuildContext context) {
  final theme = Theme.of(context);
  showModalBottomSheet(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      Widget infoRow({
        required IconData icon,
        required String label,
        required String value,
      }) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.secondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$label: ',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: value,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'About Z Music',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              infoRow(
                icon: Icons.person_outline,
                label: 'Developed by',
                value: 'Jabid Hassan',
              ),
              infoRow(
                icon: Icons.verified_outlined,
                label: 'Version',
                value: '1.0.0 (Build 2)',
              ),
              infoRow(
                icon: Icons.music_note_outlined,
                label: 'Focus',
                value: 'Offline music player with Download support',
              ),
              infoRow(
                icon: Icons.memory_outlined,
                label: 'Built with',
                value: 'Flutter',
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
