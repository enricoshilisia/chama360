import 'package:flutter/material.dart';

import '../theme/breakpoints.dart';

/// Holds a screen's content to a sensible column on a big window.
///
/// Without this every list runs the full width of a monitor, which puts a
/// member's name and their balance a foot apart. Screens that genuinely
/// want the room — a two-pane roster, a wide report table — simply don't
/// use it.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 900});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!Breakpoints.isWide(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
