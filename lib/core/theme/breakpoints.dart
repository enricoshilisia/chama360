import 'package:flutter/widgets.dart';

/// Where the layout changes shape.
///
/// Kept in one place because several screens have to agree: the shell
/// decides between a bottom bar and a side rail at the same width that the
/// dashboard decides between one column and two. If those drifted apart
/// you'd get a rail next to a phone layout, which is the thing this is
/// meant to avoid.
class Breakpoints {
  Breakpoints._();

  /// Below this, the phone layout: bottom nav, one column.
  static const double compact = 900;

  /// Above this there is room for a genuine two-pane layout — a list and
  /// the thing it's showing, side by side.
  static const double expanded = 1200;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= compact;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}
