import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../core/company_selector_chip.dart';
import '../../../core/selected_company_provider.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _company;
  int _totalDocs = 0;
  int _activeEmployees = 0;
  List<Map<String, dynamic>> _alerts = [];
  double _complianceRate = 0.0;
  int _compliantCount = 0;
  int _expiredCount = 0;
  String _whatsappNumber = '+971 50 000 0000';
  String _contactNumber = '+971 4 000 0000';
  late AnimationController _animController;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _ringAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _fetchDashboardData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchDashboardData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);

      if (companies.isEmpty) {
        // Fallback if not loaded yet
        _company = null;
        _activeEmployees = 0;
        _totalDocs = 0;
        _complianceRate = 0.0;
        _alerts = [];
        return;
      }

      List<String> targetCompanyIds = [];
      if (selectedId != null) {
        targetCompanyIds = [selectedId];
        _company = companies.firstWhere((c) => c['id'] == selectedId);
      } else {
        targetCompanyIds = companies.map((c) => c['id'] as String).toList();
        final isIndiv = companies.any((c) => c['entity_type'] == 'individual');
        _company = {'name': isIndiv ? 'All Families' : 'All Companies'};
      }

      if (targetCompanyIds.isNotEmpty) {
        final employeesRes = await supabase
            .from('employees')
            .select('*')
            .inFilter('company_id', targetCompanyIds);
        final List employees = employeesRes;
        _activeEmployees = employees.where((e) => e['status'] == 'active').length;

        final compDocsRes = await supabase
            .from('company_documents')
            .select('*, document_categories(name)')
            .inFilter('company_id', targetCompanyIds);
        final List compDocs = compDocsRes;

        final empIds = employees.map((e) => e['id']).toList();
        List empDocs = [];
        if (empIds.isNotEmpty) {
          final empDocsRes = await supabase
              .from('employee_documents')
              .select('*, employees(first_name, last_name), document_categories(name)')
              .inFilter('employee_id', empIds);
          empDocs = empDocsRes;
        }

        // Fetch active renewal requests for mapping
        final renewalsRes = await supabase
            .from('renewal_requests')
            .select('id, employee_id, document_category_id, status')
            .inFilter('company_id', targetCompanyIds)
            .inFilter('status', ['pending', 'requested', 'in_progress']);
        final List renewals = renewalsRes;

        _totalDocs = compDocs.length + empDocs.length;

        final today = DateTime.now();
        final thirtyDaysFromNow = today.add(const Duration(days: 30));
        final allDocs = [...compDocs, ...empDocs];
        _compliantCount = 0;
        _expiredCount = 0;
        _alerts = [];

        for (var doc in allDocs) {
          final expiryStr = doc['expiry_date'];
          if (expiryStr == null) {
            _compliantCount++;
            continue;
          }
          final expiry = DateTime.parse(expiryStr);
          final ownerName = doc['employees'] != null
              ? "${doc['employees']['first_name']} ${doc['employees']['last_name']}"
              : "Company Level";

          // Find matching active renewal request
          Map<String, dynamic>? activeRenewal;
          for (var r in renewals) {
            if (r['document_category_id'] == doc['category_id'] &&
                r['employee_id'] == doc['employee_id']) {
              activeRenewal = r;
              break;
            }
          }
          final renewalStatus = activeRenewal != null ? activeRenewal['status'] : null;

          if (expiry.isBefore(today)) {
            _expiredCount++;
            _alerts.add({
              'name': doc['file_name'] ?? doc['document_categories']['name'],
              'owner': ownerName,
              'expiry': expiryStr,
              'daysLeft': expiry.difference(today).inDays,
              'status': 'expired',
              'doc': doc,
              'renewalStatus': renewalStatus,
            });
          } else if (expiry.isBefore(thirtyDaysFromNow)) {
            // Expiring soon: compliant but flagged
            _compliantCount++;
            _alerts.add({
              'name': doc['file_name'] ?? doc['document_categories']['name'],
              'owner': ownerName,
              'expiry': expiryStr,
              'daysLeft': expiry.difference(today).inDays,
              'status': 'expiring_soon',
              'doc': doc,
              'renewalStatus': renewalStatus,
            });
          } else {
            _compliantCount++;
          }
        }

        if (allDocs.isNotEmpty) {
          _complianceRate = _compliantCount / allDocs.length;
        } else {
          _complianceRate = 0.0;
        }
        _alerts.sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));
      }

      // Fetch settings regardless of company status
      final settingsRes = await supabase.from('app_settings').select('*');
      final List settings = settingsRes;
      for (var setting in settings) {
        if (setting['key'] == 'support_whatsapp') {
          _whatsappNumber = setting['value'];
        } else if (setting['key'] == 'support_phone') {
          _contactNumber = setting['value'];
        }
      }
    } catch (e) {
      debugPrint("Error loading dashboard: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _animController.forward(from: 0.0);
      }
    }
  }

  Future<void> _submitRenewRequest(Map<String, dynamic> alert) async {
    try {
      final doc = alert['doc'];
      final companyId = _company?['id'];
      if (companyId == null || doc == null) return;
      
      final docCatId = doc['category_id'];
      final employeeId = doc['employee_id'];

      // Spam prevention check
      var checkQuery = supabase
          .from('renewal_requests')
          .select('id')
          .eq('company_id', companyId)
          .eq('document_category_id', docCatId)
          .inFilter('status', ['pending', 'requested', 'in_progress']);

      if (employeeId != null) {
        checkQuery = checkQuery.eq('employee_id', employeeId);
      } else {
        checkQuery = checkQuery.filter('employee_id', 'is', null);
      }

      final existing = await checkQuery;
      if (existing.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A renewal request for this document is already active.'),
              backgroundColor: TerraTheme.error,
            ),
          );
        }
        return;
      }

      await supabase.from('renewal_requests').insert({
        'company_id': companyId,
        'employee_id': employeeId,
        'document_category_id': docCatId,
        'details': 'Automated renewal request via app for ${alert['name']}',
        'status': 'requested',
      });

      if (mounted) {
        setState(() {
          alert['renewalStatus'] = 'requested';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Renewal request submitted for ${alert['name']}'),
            backgroundColor: TerraTheme.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error submitting renewal request: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit renewal request'),
            backgroundColor: TerraTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedCompanyIdProvider, (previous, next) {
      _fetchDashboardData();
    });

    // Watch availableCompaniesProvider so we rebuild if it loads/updates
    ref.watch(availableCompaniesProvider);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: TerraTheme.cream50,
        body: Center(
          child: CircularProgressIndicator(color: TerraTheme.gold500),
        ),
      );
    }

    final isIndividual = ref.watch(isIndividualProvider);
    final companyName = _company?['name'] ?? 
        (isIndividual ? 'Your Family' : 'Your Company');
    final compliancePct = (_complianceRate * 100).toInt();

    return Scaffold(
      backgroundColor: TerraTheme.cream50,
      body: CustomScrollView(
        slivers: [
          // ── Top App Bar ──────────────────────────────────────────
          SliverAppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            shadowColor: const Color(0x143D4A2A),
            surfaceTintColor: Colors.transparent,
            pinned: true,
            titleSpacing: 16,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: TerraTheme.olive900,
                  backgroundImage: (_company?['logo_url'] != null && _company!['logo_url'].toString().isNotEmpty)
                      ? NetworkImage(_company!['logo_url'])
                      : null,
                  child: (_company?['logo_url'] == null || _company!['logo_url'].toString().isEmpty)
                      ? Center(
                          child: Text('PR',
                              style: GoogleFonts.nunitoSans(
                                color: TerraTheme.gold500,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              )),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Text('PRO Services',
                    style: GoogleFonts.nunitoSans(
                      color: TerraTheme.olive900,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    )),
              ],
            ),
            actions: [
              IconButton(
                icon: Stack(children: [
                  const Icon(Icons.notifications_outlined, color: TerraTheme.olive900, size: 26),
                  Positioned(
                    top: 2, right: 2,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xff834751),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ]),
                onPressed: () {},
              ),

              const SizedBox(width: 4),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Welcome Hero ─────────────────────────────────
                  Text('PREMIUM PORTAL',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: TerraTheme.neutral500,
                      )),
                  const SizedBox(height: 4),
                  Text('Welcome back,',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TerraTheme.charcoal800,
                        height: 1.1,
                      )),
                  Text(companyName,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TerraTheme.primary,
                        height: 1.2,
                      )),
                  const CompanySelectorChip(),

                  const SizedBox(height: 16),

                  // ── Compliance Ring Card ──────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [BoxShadow(color: Color(0x143D4A2A), blurRadius: 20, offset: Offset(0, 4))],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _ringAnim,
                          builder: (context, _) {
                            return SizedBox(
                              width: 176,
                              height: 176,
                              child: CustomPaint(
                                painter: _ComplianceRingPainter(
                                  progress: _ringAnim.value * _complianceRate,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('$compliancePct%',
                                          style: GoogleFonts.nunitoSans(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w800,
                                            color: TerraTheme.olive900,
                                          )),
                                      Text('Compliant',
                                          style: GoogleFonts.nunitoSans(
                                            fontSize: 13,
                                            color: TerraTheme.neutral500,
                                            fontWeight: FontWeight.w600,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isIndividual
                              ? 'Overall compliance score based on\ncurrent document validity and family member status.'
                              : 'Overall compliance score based on\ncurrent document validity and employee status.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            color: TerraTheme.neutral500,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Stats Grid ────────────────────────────────────
                  Row(
                    children: [
                      _StatCard(
                        value: '$_activeEmployees',
                        label: isIndividual ? 'FAMILY\nMEMBERS' : 'EMPLOYEES',
                        borderColor: TerraTheme.warning,
                      ),
                      const SizedBox(width: 10),
                      _StatCard(value: '$_totalDocs', label: 'TOTAL\nDOCUMENTS', borderColor: TerraTheme.primary),
                      const SizedBox(width: 10),
                      _StatCard(value: _expiredCount.toString().padLeft(2, '0'), label: 'EXPIRED\nDOCS', borderColor: TerraTheme.error),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── Action Required ─────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Action Required',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: TerraTheme.olive900,
                          )),
                      InkWell(
                        onTap: () {
                          // Filter alerts to only show expired/expiring_soon just in case
                          final expiringAlerts = _alerts.where((a) => a['status'] == 'expired' || a['status'] == 'expiring_soon').toList();
                          context.push('/action_required', extra: expiringAlerts);
                        },
                        child: Text('View All',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TerraTheme.primary,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_alerts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: TerraTheme.olive100),
                      ),
                      child: Center(
                        child: Text('All documents are compliant ✓',
                            style: GoogleFonts.nunitoSans(color: TerraTheme.primary, fontWeight: FontWeight.w600)),
                      ),
                    )
                  else
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final alert = _alerts[i];
                          final isExpired = alert['status'] == 'expired';
                          return _ExpiryCard(
                            alert: alert,
                            isExpired: isExpired,
                            onRenew: () => _submitRenewRequest(alert),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ── Dark CTA Card ─────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: TerraTheme.olive900,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        // dot pattern
                        Positioned.fill(
                          child: CustomPaint(painter: _DotPatternPainter()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Need Quick Renewal?',
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: TerraTheme.gold500,
                                  )),
                              const SizedBox(height: 8),
                              Text(
                                  isIndividual
                                      ? 'Connect with our specialized PRO team for expedited processing of your family visas and documents.'
                                      : 'Connect with our specialized PRO team for expedited processing of your expiring documents.',
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 14,
                                    color: const Color(0xCCE8ECDE),
                                    height: 1.5,
                                  )),
                              const SizedBox(height: 20),
                              // Primary gold CTA
                              ElevatedButton.icon(
                                onPressed: () => context.push('/support/renew'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: TerraTheme.gold500,
                                  foregroundColor: TerraTheme.charcoal800,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.bolt_rounded, size: 20),
                                label: Text('Request Quick Renewal',
                                    style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w800, fontSize: 15)),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final url = Uri.parse('https://wa.me/${_whatsappNumber.replaceAll(' ', '').replaceAll('+', '')}');
                                        try {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        } catch (e) {
                                          debugPrint('Could not launch WhatsApp: $e');
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Could not open WhatsApp.')),
                                            );
                                          }
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: TerraTheme.gold500,
                                        side: const BorderSide(color: Color(0x4DC9A227)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                      ),
                                      icon: const Icon(Icons.chat_outlined, size: 18),
                                      label: Text('WhatsApp',
                                          style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final url = Uri.parse('tel:${_contactNumber.replaceAll(' ', '')}');
                                        try {
                                          await launchUrl(url);
                                        } catch (e) {
                                          debugPrint('Could not launch Dialer: $e');
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: TerraTheme.gold500,
                                        side: const BorderSide(color: Color(0x4DC9A227)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                      ),
                                      icon: const Icon(Icons.call_outlined, size: 18),
                                      label: Text('Call Support',
                                          style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, fontSize: 13)),
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

                  const SizedBox(height: 16),

                  // ── Dubai banner ──────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 140,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xff3D4A2A), Color(0xff6B7A4C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(child: CustomPaint(painter: _DotPatternPainter())),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                    isIndividual
                                        ? 'Need visa assistance?'
                                        : 'Expanding your business?',
                                    style: GoogleFonts.nunitoSans(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    )),
                                Text(
                                    isIndividual
                                        ? 'Talk to our experts about family visa services'
                                        : 'Talk to our experts about visa services',
                                    style: GoogleFonts.nunitoSans(
                                      color: TerraTheme.gold200,
                                      fontSize: 13,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat Card Widget ───────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color borderColor;

  const _StatCard({required this.value, required this.label, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x143D4A2A), blurRadius: 16, offset: Offset(0, 4))],
          border: Border(bottom: BorderSide(color: borderColor, width: 4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: GoogleFonts.nunitoSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: TerraTheme.charcoal800,
                )),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunitoSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: TerraTheme.neutral500,
                  letterSpacing: 0.5,
                  height: 1.3,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Expiry Card Widget ────────────────────────────────────────────────────────
class _ExpiryCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final bool isExpired;
  final VoidCallback onRenew;

  const _ExpiryCard({required this.alert, required this.isExpired, required this.onRenew});

  @override
  Widget build(BuildContext context) {
    final statusColor = isExpired ? TerraTheme.error : TerraTheme.warning;
    final statusLabel = isExpired ? 'EXPIRED' : 'EXPIRING SOON';

    final renewalStatus = alert['renewalStatus'];
    final hasActiveRequest = renewalStatus != null;

    String buttonText = 'Renew Request';
    Color borderColor = TerraTheme.primary;
    Color textColor = TerraTheme.primary;
    Color? bgColor;

    if (renewalStatus == 'pending' || renewalStatus == 'requested') {
      buttonText = 'Requested';
      borderColor = TerraTheme.neutral500;
      textColor = TerraTheme.neutral500;
      bgColor = TerraTheme.neutral500.withOpacity(0.08);
    } else if (renewalStatus == 'in_progress') {
      buttonText = 'In Progress';
      borderColor = TerraTheme.gold500;
      textColor = TerraTheme.gold500;
      bgColor = TerraTheme.gold500.withOpacity(0.08);
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TerraTheme.olive100),
        boxShadow: const [BoxShadow(color: Color(0x0A3D4A2A), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: TerraTheme.gold200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sync_rounded, color: TerraTheme.olive900, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(statusLabel,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      letterSpacing: 0.5,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(alert['name'] ?? 'Document',
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: TerraTheme.olive900,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(alert['owner'] ?? '',
              style: GoogleFonts.nunitoSans(fontSize: 12, color: TerraTheme.neutral500)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton(
              onPressed: hasActiveRequest ? null : onRenew,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: bgColor,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                buttonText,
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Compliance Ring Painter ───────────────────────────────────────────────────
class _ComplianceRingPainter extends CustomPainter {
  final double progress;
  _ComplianceRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 10;
    const strokeW = 12.0;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Background ring
    canvas.drawArc(
      rect, 0, 2 * math.pi, false,
      Paint()
        ..color = TerraTheme.olive100
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );

    // Progress arc
    canvas.drawArc(
      rect, -math.pi / 2, 2 * math.pi * progress, false,
      Paint()
        ..color = TerraTheme.gold500
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ComplianceRingPainter old) => old.progress != progress;
}

// ── Dot Pattern Painter ───────────────────────────────────────────────────────
class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x1AC9A227);
    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
