import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/supabase_client.dart';
import '../../../core/selected_company_provider.dart';
import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/local_storage_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _persistReadToServer(List<String> ids) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || ids.isEmpty) return;

    try {
      final rows = ids
          .map((id) => {'user_id': userId, 'notification_id': id})
          .toList();
      await supabase
          .from('notification_reads')
          .upsert(rows, onConflict: 'user_id,notification_id');
    } catch (e) {
      // Table may not exist yet if migration not applied — local storage still works
      debugPrint('notification_reads upsert skipped: $e');
    }
  }

  Future<void> _fetchNotifications() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final companies = ref.read(availableCompaniesProvider);
      final companyIds = companies.map((c) => c['id'] as String).toList();

      List<Map<String, dynamic>> results = [];

      // Broadcast notifications (null company_id)
      final broadcastRes = await supabase
          .from('notifications')
          .select('*')
          .filter('company_id', 'is', null)
          .order('created_at', ascending: false);
      results.addAll(List<Map<String, dynamic>>.from(broadcastRes));

      // Company-targeted notifications
      if (companyIds.isNotEmpty) {
        final targetedRes = await supabase
            .from('notifications')
            .select('*')
            .inFilter('company_id', companyIds)
            .order('created_at', ascending: false);
        results.addAll(List<Map<String, dynamic>>.from(targetedRes));
      }

      // Sort descending
      results.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
        final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      // Load local + server read state
      await ref.read(readIdsProvider.notifier).ensureLoaded();
      final localReadIds = ref.read(readIdsProvider);

      Set<String> serverReadIds = {};
      try {
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final reads = await supabase
              .from('notification_reads')
              .select('notification_id')
              .eq('user_id', userId);
          serverReadIds = {
            for (final r in reads as List)
              if (r['notification_id'] != null) r['notification_id'].toString(),
          };
          if (serverReadIds.isNotEmpty) {
            ref.read(readIdsProvider.notifier).addAll(serverReadIds.toList());
          }
        }
      } catch (e) {
        debugPrint('notification_reads fetch skipped: $e');
      }

      final readIds = {...localReadIds, ...serverReadIds};

      for (final n in results) {
        final id = n['id']?.toString();
        if (id != null && readIds.contains(id)) {
          n['is_read'] = true;
        } else {
          // Ignore global is_read — it is shared across all clients
          n['is_read'] = false;
        }
      }

      if (mounted) {
        setState(() => _notifications = results);
        final unread = results.where((n) => n['is_read'] != true).length;
        ref.read(unreadNotifCountProvider.notifier).state = unread;
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> notif) async {
    if (notif['is_read'] == true) return;
    final id = notif['id']?.toString() ?? '';
    if (id.isEmpty) return;

    setState(() => notif['is_read'] = true);

    ref.read(readIdsProvider.notifier).add(id);

    final count = ref.read(unreadNotifCountProvider);
    if (count > 0) {
      ref.read(unreadNotifCountProvider.notifier).state = count - 1;
    }

    await _persistReadToServer([id]);
  }

  Future<void> _markAllRead() async {
    final unreadIds = _notifications
        .where((n) => n['is_read'] != true)
        .map((n) => n['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (unreadIds.isEmpty) return;

    setState(() {
      for (final n in _notifications) {
        n['is_read'] = true;
      }
    });

    ref.read(readIdsProvider.notifier).addAll(unreadIds);
    ref.read(unreadNotifCountProvider.notifier).state = 0;

    await _persistReadToServer(unreadIds);
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'alert':
        return Icons.warning_rounded;
      case 'expiry':
        return Icons.event_busy_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'alert':
        return TerraTheme.error;
      case 'expiry':
        return TerraTheme.warning;
      default:
        return TerraTheme.primary;
    }
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((n) => n['is_read'] != true)
        .length;

    return Scaffold(
      backgroundColor: TerraTheme.cream50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: TerraTheme.olive900,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  'PR',
                  style: GoogleFonts.nunitoSans(
                    color: TerraTheme.gold500,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'PRO Services',
                style: GoogleFonts.nunitoSans(
                  color: TerraTheme.olive900,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TerraTheme.primary,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: TerraTheme.gold500,
        onRefresh: _fetchNotifications,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: TerraTheme.olive900,
                      ),
                    ),
                    if (unreadCount > 0)
                      Text(
                        '$unreadCount unread',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          color: TerraTheme.neutral500,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: TerraTheme.gold500),
                ),
              )
            else if (_notifications.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 56,
                        color: TerraTheme.olive100,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No notifications yet',
                        style: GoogleFonts.nunitoSans(
                          color: TerraTheme.neutral500,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You\'ll see alerts and updates here.',
                        style: GoogleFonts.nunitoSans(
                          color: TerraTheme.neutral500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final notif = _notifications[i];
                    final type = notif['type'] as String?;
                    final isUnread = notif['is_read'] != true;
                    final color = _typeColor(type);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _markRead(notif),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isUnread
                                ? color.withOpacity(0.04)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isUnread
                                  ? color.withOpacity(0.25)
                                  : TerraTheme.olive100,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A3D4A2A),
                                blurRadius: 12,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _typeIcon(type),
                                    color: color,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              notif['title'] ?? '',
                                              style: GoogleFonts.nunitoSans(
                                                fontSize: 14,
                                                fontWeight: isUnread
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                color: TerraTheme.olive900,
                                              ),
                                            ),
                                          ),
                                          if (isUnread)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              margin: const EdgeInsets.only(
                                                left: 6,
                                                top: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        notif['message'] ?? '',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 13,
                                          color: TerraTheme.neutral500,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(50),
                                            ),
                                            child: Text(
                                              (type ?? 'info').toUpperCase(),
                                              style: GoogleFonts.nunitoSans(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: color,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _timeAgo(notif['created_at']),
                                            style: GoogleFonts.nunitoSans(
                                              fontSize: 11,
                                              color: TerraTheme.neutral500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: _notifications.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
