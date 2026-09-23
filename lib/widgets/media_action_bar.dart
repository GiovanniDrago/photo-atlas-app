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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            for (final action in actions)
              Expanded(
                child: TextButton.icon(
                  onPressed: action.onPressed,
                  icon: Icon(action.icon),
                  label: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
