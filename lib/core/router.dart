import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/dashboard/presentation/action_required_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/employees/presentation/employees_screen.dart';
import '../features/employees/presentation/employee_detail_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/support/presentation/renewal_request_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import 'supabase_client.dart';
import 'selected_company_provider.dart';
import 'notification_service.dart';
import 'local_storage_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final publicRoutes = ['/login', '/forgot-password', '/reset-password'];
      final isPublicRoute = publicRoutes.contains(state.matchedLocation);

      if (session == null) {
        return isPublicRoute ? null : '/login';
      }
      if (isPublicRoute) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      ShellRoute(
        pageBuilder: (context, state, child) {
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: AppShell(child: child),
            transitionDuration: const Duration(milliseconds: 260),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final offsetTween = Tween<Offset>(
                    begin: const Offset(0.0, 0.08),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic));
                  final fadeTween = Tween<double>(
                    begin: 0.0,
                    end: 1.0,
                  ).chain(CurveTween(curve: Curves.easeOutCubic));
                  return FadeTransition(
                    opacity: animation.drive(fadeTween),
                    child: SlideTransition(
                      position: animation.drive(offsetTween),
                      child: child,
                    ),
                  );
                },
          );
        },
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
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) => buildSlideTransitionPage(
              child: const NotificationsScreen(),
              state: state,
            ),
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
      final tween = Tween(
        begin: begin,
        end: end,
      ).chain(CurveTween(curve: curve));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

// ── Unread count provider ─────────────────────────────────────────────────────
final unreadNotifCountProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;
  final _appLinks = AppLinks();
  bool _isNavigatingToReset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await fetchUserCompanies(ref);
      _subscribeNotifications();
      _fetchUnreadCount();
      _setupPushNotifications();
      _listenForForegroundNotifications();
      _handleInitialLink();
      _listenToLinks();
    });
  }

  @override
  void dispose() {
    NotificationService.instance.unsubscribe();
    super.dispose();
  }

  // ─── Push Notifications Setup ───────────────────────────────────────────────

  Future<void> _setupPushNotifications() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission (iOS / Android 13+)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    // Ensure high-priority delivery on Android when app is backgrounded/killed
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _saveFcmToken(await messaging.getToken());

    // Token can rotate — keep Supabase in sync
    messaging.onTokenRefresh.listen(_saveFcmToken);
  }

  Future<void> _saveFcmToken(String? fcmToken) async {
    if (fcmToken == null || fcmToken.isEmpty) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Correct table is `users` (there is no `profiles` table)
      await supabase
          .from('users')
          .update({'fcm_token': fcmToken})
          .eq('id', userId);
      debugPrint('FCM Token saved: $fcmToken');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  Future<void> _handleInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('App opened from initial link: $initialUri');
        _handleResetPasswordLink(initialUri);
      }
    } catch (e) {
      debugPrint('Error getting initial link: $e');
    }
  }

  void _listenToLinks() {
    _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('App opened from link: $uri');
        _handleResetPasswordLink(uri);
      },
      onError: (e) {
        debugPrint('Error listening to links: $e');
      },
    );
  }

  void _handleResetPasswordLink(Uri uri) {
    // Check if this is a password reset link
    if (uri.host == 'reset-password' || uri.path == '/reset-password') {
      debugPrint('Navigating to reset password screen');
      // Navigate to reset password screen
      if (!_isNavigatingToReset) {
        _isNavigatingToReset = true;
        Future.delayed(Duration.zero, () {
          if (mounted) {
            // Check if user is logged in
            final session = supabase.auth.currentSession;
            if (session != null) {
              // User is logged in, navigate to reset password
              setState(() {
                _currentIndex = 4; // Profile tab
              });
              context.go('/reset-password');
            } else {
              // User is not logged in, navigate to login first
              // The reset token will be handled by Supabase after login
              context.go('/login');
            }
            _isNavigatingToReset = false;
          }
        });
      }
    }
  }

  void _listenForForegroundNotifications() {
    // Foreground: FCM does not auto-display — show a local banner
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      final notification = message.notification;
      final title =
          notification?.title ??
          message.data['title']?.toString() ??
          'PRO Services';
      final body =
          notification?.body ??
          message.data['body']?.toString() ??
          message.data['message']?.toString() ??
          '';

      NotificationService.instance.showLocalNotification(
        id: NotificationService.instance.idFromUuid(
          message.messageId ?? DateTime.now().toString(),
        ),
        title: title,
        body: body,
      );
      _fetchUnreadCount();
    });

    // User tapped a notification that opened the app from background/killed
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification opened app: ${message.messageId}');
      _fetchUnreadCount();
    });

    // App launched from a terminated state via notification tap
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint('Launched from notification: ${message.messageId}');
        _fetchUnreadCount();
      }
    });
  }

  void _subscribeNotifications() {
    final companies = ref.read(availableCompaniesProvider);
    final companyIds = companies.map((c) => c['id'] as String).toList();
    NotificationService.instance.subscribe(
      companyIds,
      onNotificationChange: () {
        if (mounted) {
          _fetchUnreadCount();
        }
      },
    );
  }

  Future<void> _fetchUnreadCount() async {
    try {
      // Wait for locally-persisted read IDs so count survives app restart
      await ref.read(readIdsProvider.notifier).ensureLoaded();
      final readIds = ref.read(readIdsProvider);

      final companies = ref.read(availableCompaniesProvider);
      final companyIds = companies.map((c) => c['id'] as String).toList();

      final Set<String> allIds = {};

      // Broadcast notifications
      final broadcastRes = await supabase
          .from('notifications')
          .select('id')
          .filter('company_id', 'is', null);
      for (final row in broadcastRes as List) {
        final id = row['id']?.toString();
        if (id != null) allIds.add(id);
      }

      // Company-targeted notifications
      if (companyIds.isNotEmpty) {
        final targetedRes = await supabase
            .from('notifications')
            .select('id')
            .inFilter('company_id', companyIds);
        for (final row in targetedRes as List) {
          final id = row['id']?.toString();
          if (id != null) allIds.add(id);
        }
      }

      // Prefer server-side per-user reads when available; fall back to local
      Set<String> serverReadIds = {};
      try {
        final userId = supabase.auth.currentUser?.id;
        if (userId != null && allIds.isNotEmpty) {
          final reads = await supabase
              .from('notification_reads')
              .select('notification_id')
              .eq('user_id', userId);
          serverReadIds = {
            for (final r in reads as List)
              if (r['notification_id'] != null) r['notification_id'].toString(),
          };
          // Merge server reads into local storage so offline restarts stay correct
          if (serverReadIds.isNotEmpty) {
            ref.read(readIdsProvider.notifier).addAll(serverReadIds.toList());
          }
        }
      } catch (e) {
        debugPrint('notification_reads fetch skipped: $e');
      }

      final effectiveRead = {...readIds, ...serverReadIds};
      final count = allIds.where((id) => !effectiveRead.contains(id)).length;

      if (mounted) {
        ref.read(unreadNotifCountProvider.notifier).state = count;
      }
    } catch (e) {
      debugPrint('Error fetching unread count: $e');
    }
  }

  void _onTabTapped(BuildContext context, int index) {
    setState(() => _currentIndex = index);
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
    final isLoading = ref.watch(companiesLoadingProvider);
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xff316342)),
        ),
      );
    }

    final isIndividual = ref.watch(isIndividualProvider);
    final unreadCount = ref.watch(unreadNotifCountProvider);

    return Scaffold(
      body: widget.child,
      // Bell icon floats above the bottom nav as an overlay on the app bar
      // Each screen's own AppBar has a notification bell — we pass unreadCount
      // via the provider so any screen can read it.
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => _onTabTapped(context, index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xff316342),
        unselectedItemColor: const Color(0xff8a8a80),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.description_outlined),
            activeIcon: const Icon(Icons.description),
            label: isIndividual ? 'My Docs' : 'Company',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.badge_outlined),
            activeIcon: const Icon(Icons.badge),
            label: isIndividual ? 'Family' : 'Employee',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.help_outline),
            activeIcon: Icon(Icons.help),
            label: 'Support',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            activeIcon: const Icon(Icons.account_circle),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ── Bell icon widget — used in any screen's AppBar actions ───────────────────
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotifCountProvider);

    return IconButton(
      onPressed: () => context.push('/notifications'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            unreadCount > 0
                ? Icons.notifications_rounded
                : Icons.notifications_outlined,
            color: unreadCount > 0
                ? const Color(0xff834751)
                : const Color(0xff3D4A2A),
          ),
          if (unreadCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xffc0392b),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
