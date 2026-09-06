import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/chama/presentation/screens/add_member_screen.dart';
import '../../features/chama/presentation/screens/chama_detail_screen.dart';
import '../../features/chama/presentation/screens/chama_members_screen.dart';
import '../../features/chama/presentation/screens/join_chama_screen.dart';
import '../../features/chama/presentation/screens/member_detail_screen.dart';
import '../../features/chama/presentation/screens/my_chamas_screen.dart';
import '../../features/chama/presentation/screens/register_chama_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/loans/presentation/screens/loan_detail_screen.dart';
import '../../features/loans/presentation/screens/loans_screen.dart';
import '../../features/loans/presentation/screens/record_loan_screen.dart';
import '../../features/loans/presentation/screens/request_loan_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import 'app_shell.dart';
import 'go_router_refresh_stream.dart';
import 'transitions.dart';

/// Every route lives inside its tab's branch navigator (not the root), so
/// the bottom nav bar in AppShell stays visible everywhere — including on
/// chama detail, members, and loan screens. AppShell's `extendBody: true`
/// lets its frosted nav bar float over content, which means every
/// scrollable screen needs enough bottom padding to clear it — see
/// core/theme/layout.dart's kShellBottomInset, applied on each screen's
/// list/scroll view padding. Quick one-field actions (add a contribution)
/// use a modal bottom sheet instead of a route at all.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(authRepo.authStateChanges),
    redirect: (context, state) {
      final loggedIn = authRepo.currentUser != null;
      final onAuthScreen =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';

      if (!loggedIn && !onAuthScreen) return '/login';
      if (loggedIn && onAuthScreen) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          currentIndex: navigationShell.currentIndex,
          onTap: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
          child: navigationShell,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (context, state) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/chamas',
              builder: (context, state) => const MyChamasScreen(),
              routes: [
                GoRoute(
                  path: 'create',
                  pageBuilder: (context, state) =>
                      fadeThroughPage(state: state, child: const RegisterChamaScreen()),
                ),
                GoRoute(
                  path: 'join',
                  pageBuilder: (context, state) =>
                      fadeThroughPage(state: state, child: const JoinChamaScreen()),
                ),
                GoRoute(
                  path: ':id',
                  pageBuilder: (context, state) => fadeThroughPage(
                    state: state,
                    child: ChamaDetailScreen(chamaId: state.pathParameters['id']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'members',
                      pageBuilder: (context, state) => fadeThroughPage(
                        state: state,
                        child: ChamaMembersScreen(chamaId: state.pathParameters['id']!),
                      ),
                      routes: [
                        GoRoute(
                          path: 'add',
                          pageBuilder: (context, state) => fadeThroughPage(
                            state: state,
                            child: AddMemberScreen(chamaId: state.pathParameters['id']!),
                          ),
                        ),
                        GoRoute(
                          path: ':memberId',
                          pageBuilder: (context, state) => fadeThroughPage(
                            state: state,
                            child: MemberDetailScreen(
                              chamaId: state.pathParameters['id']!,
                              memberId: state.pathParameters['memberId']!,
                            ),
                          ),
                        ),
                      ],
                    ),
                    GoRoute(
                      path: 'loans',
                      pageBuilder: (context, state) => fadeThroughPage(
                        state: state,
                        child: LoansScreen(chamaId: state.pathParameters['id']!),
                      ),
                      routes: [
                        GoRoute(
                          path: 'request',
                          pageBuilder: (context, state) => fadeThroughPage(
                            state: state,
                            child: RequestLoanScreen(
                              chamaId: state.pathParameters['id']!,
                              memberId: state.extra as String,
                            ),
                          ),
                        ),
                        GoRoute(
                          path: 'record',
                          pageBuilder: (context, state) => fadeThroughPage(
                            state: state,
                            child: RecordLoanScreen(chamaId: state.pathParameters['id']!),
                          ),
                        ),
                        GoRoute(
                          path: ':loanId',
                          pageBuilder: (context, state) => fadeThroughPage(
                            state: state,
                            child: LoanDetailScreen(
                              chamaId: state.pathParameters['id']!,
                              loanId: state.pathParameters['loanId']!,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notifications',
              builder: (context, state) => const NotificationsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
