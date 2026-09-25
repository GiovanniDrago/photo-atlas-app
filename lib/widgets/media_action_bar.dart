import 'package:flutter/material.dart';

class MediaActionButton {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const MediaActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });
}

/// Bottom action bar shown while items are selected (gallery, timeline).
class MediaActionBar extends StatelessWidget {
  final List<MediaActionButton> actions;

  const MediaActionBar({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final action in actions)
        TextButton.icon(
          onPressed: action.onPressed,
          icon: Icon(action.icon),
          label: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        // Up to four actions share the width; more scroll horizontally so the
        // album bar (upload/share/download/delete/remove/cover) stays usable.
        child: actions.length <= 4
            ? Row(
                children: [
                  for (final button in buttons) Expanded(child: button),
                ],
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final button in buttons)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: button,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
