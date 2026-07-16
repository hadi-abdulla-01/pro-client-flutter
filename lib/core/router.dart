import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/dashboard/presentation/action_required_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/employees/presentation/employees_screen.dart';
import '../features/employees/presentation/employee_detail_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/support/presentation/renewal_request_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import 'supabase_client.dart';
import 'selected_company_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final loggingIn = state.matchedLocation == '/login';

      if (session == null) {
        return loggingIn ? null : '/login';
      }

      if (loggingIn) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/action_required',
            pageBuilder: (context, state) {
              final alerts = state.extra as List<Map<String, dynamic>>? ?? [];
              return buildSlideTransitionPage(
                child: ActionRequiredScreen(alerts: alerts),
                state: state,
              );
            },
          ),
          GoRoute(
            path: '/documents',
            builder: (context, state) => const DocumentsScreen(),
          ),
          GoRoute(
            path: '/employees',
            builder: (context, state) => const EmployeesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final employeeId = state.pathParameters['id']!;
                  return buildSlideTransitionPage(
                    child: EmployeeDetailScreen(employeeId: employeeId),
                    state: state,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/support',
            builder: (context, state) => const SupportScreen(),
            routes: [
              GoRoute(
                path: 'renew',
                pageBuilder: (context, state) => buildSlideTransitionPage(
                  child: const RenewalRequestScreen(),
                  state: state,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage<void> buildSlideTransitionPage({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeOutCubic;
      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      var offsetAnimation = animation.drive(tween);
      return SlideTransition(
        position: offsetAnimation,
        child: child,
      );
    },
  );
}

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchUserCompanies(ref);
    });
  }

  void _onTabTapped(BuildContext context, int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/documents');
        break;
      case 2:
        context.go('/employees');
        break;
      case 3:
        context.go('/support');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIndividual = ref.watch(isIndividualProvider);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => _onTabTapped(context, index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xff316342),
        unselectedItemColor: const Color(0xff8a8a80),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          const BottomNavigationBarItem(icon: Icon(Icons.description_outlined), activeIcon: Icon(Icons.description), label: 'Docs'),
          BottomNavigationBarItem(
            icon: const Icon(Icons.badge_outlined), 
            activeIcon: const Icon(Icons.badge), 
            label: isIndividual ? 'Family' : 'Employees',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.help_outline), activeIcon: Icon(Icons.help), label: 'Support'),
          const BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), activeIcon: Icon(Icons.account_circle), label: 'Profile'),
        ],
      ),
    );
  }
}
