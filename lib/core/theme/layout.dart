/// AppShell's bottom nav bar is translucent and floats over content
/// (`extendBody: true`), so every scrollable screen needs this much extra
/// bottom padding to keep its last item — especially a trailing button —
/// from landing underneath the bar instead of above it.
const double kShellBottomInset = 110;

/// Same idea, sized for a FloatingActionButton instead of scroll content —
/// wrap `floatingActionButton:` in `Padding(bottom: kFabBottomInset)` on any
/// screen living inside the shell.
const double kFabBottomInset = 70;

