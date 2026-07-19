import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/company_selector_chip.dart';
import '../../../core/selected_company_provider.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import '../../../core/router.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tickets = [];
  Map<String, dynamic>? _company;
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitting = false;
  String _whatsappNumber = '+971 50 000 0000';
  String _contactNumber = '+971 4 000 0000';

  // FAQ expand state
  final List<bool> _faqExpanded = [false, false, false];
  static const List<Map<String, String>> _faqs = [
    {
      'q': 'How long does a visa renewal take?',
      'a': 'Standard visa renewals typically take 5–7 working days. Express services are available for urgent requests.',
    },
    {
      'q': 'Can I update my company documents?',
      'a': "No, clients cannot upload documents directly. Please contact your dedicated PRO or concierge to update your documents.",
    },
    {
      'q': 'What is the "Emergency Support" line?',
      'a': 'Our emergency line is available 24/7 for critical legal or logistical issues involving government authorities that require immediate PRO intervention.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);

      if (companies.isEmpty) {
        _tickets = [];
        _company = null;
        return;
      }

      List<String> targetCompanyIds = [];
      if (selectedId != null) {
        targetCompanyIds = [selectedId];
        _company = companies.firstWhere((c) => c['id'] == selectedId);
      } else {
        targetCompanyIds = companies.map((c) => c['id'] as String).toList();
        _company = companies.first; // fallback for phone number
      }

      if (targetCompanyIds.isNotEmpty) {
        final res = await supabase
            .from('support_requests')
            .select('*')
            .inFilter('company_id', targetCompanyIds)
            .order('created_at', ascending: false);
        _tickets = List<Map<String, dynamic>>.from(res);
      }

      // Fetch settings for support numbers
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
      debugPrint("Error loading support tickets: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToRaiseRenewal() async {
    // Show a brief loading indicator while we fetch the alerts
    setState(() => _isLoading = true);
    try {
      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);

      if (companies.isEmpty) {
        if (mounted) context.push('/action_required', extra: <Map<String, dynamic>>[]);
        return;
      }

      List<String> targetCompanyIds = selectedId != null
          ? [selectedId]
          : companies.map((c) => c['id'] as String).toList();

      // Fetch employees
      final employeesRes = await supabase
          .from('employees')
          .select('*')
          .inFilter('company_id', targetCompanyIds);
      final List employees = employeesRes;

      // Fetch company-level documents
      final compDocsRes = await supabase
          .from('company_documents')
          .select('*, document_categories(name)')
          .inFilter('company_id', targetCompanyIds);
      final List compDocs = compDocsRes;

      // Fetch employee-level documents
      final empIds = employees.map((e) => e['id']).toList();
      List empDocs = [];
      if (empIds.isNotEmpty) {
        final empDocsRes = await supabase
            .from('employee_documents')
            .select('*, employees(first_name, last_name), document_categories(name)')
            .inFilter('employee_id', empIds);
        empDocs = empDocsRes;
      }

      // Fetch active renewal requests for status mapping
      final renewalsRes = await supabase
          .from('renewal_requests')
          .select('id, employee_id, document_category_id, status')
          .inFilter('company_id', targetCompanyIds)
          .inFilter('status', ['pending', 'requested', 'in_progress']);
      final List renewals = renewalsRes;

      final today = DateTime.now();
      final thirtyDays = today.add(const Duration(days: 30));
      final allDocs = [...compDocs, ...empDocs];
      final List<Map<String, dynamic>> alerts = [];

      for (var doc in allDocs) {
        final expiryStr = doc['expiry_date'];
        if (expiryStr == null) continue;
        final expiry = DateTime.tryParse(expiryStr.toString());
        if (expiry == null) continue;

        // Only include expired or expiring-soon docs
        final bool isExpired = expiry.isBefore(today);
        final bool isExpiringSoon = !isExpired && expiry.isBefore(thirtyDays);
        if (!isExpired && !isExpiringSoon) continue;

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

        alerts.add({
          'name': doc['file_name'] ?? doc['document_categories']['name'],
          'owner': ownerName,
          'expiry': expiryStr,
          'daysLeft': expiry.difference(today).inDays,
          'status': isExpired ? 'expired' : 'expiring_soon',
          'doc': doc,
          'renewalStatus': activeRenewal?['status'],
        });
      }

      alerts.sort((a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int));

      if (mounted) context.push('/action_required', extra: alerts);
    } catch (e) {
      debugPrint("Error fetching alerts for renewal: $e");
      if (mounted) context.push('/action_required', extra: <Map<String, dynamic>>[]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchWhatsApp() async {
    final uri = Uri.parse("https://wa.me/${_whatsappNumber.replaceAll(' ', '').replaceAll('+', '')}");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch WhatsApp: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
    }
  }

  Future<void> _launchCall() async {
    final uri = Uri.parse("tel:${_contactNumber.replaceAll(' ', '')}");
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('Could not launch Dialer: $e');
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);
      final companyId = selectedId ?? (companies.isNotEmpty ? companies.first['id'] : null);

      if (companyId != null) {
        await supabase.from('support_requests').insert({
          'company_id': companyId,
          'user_id': userId,
          'subject': _subjectController.text.trim(),
          'message': _messageController.text.trim(),
          'status': 'open',
          'priority': 'medium',
        });
        _subjectController.clear();
        _messageController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Support ticket submitted!'), backgroundColor: TerraTheme.primary),
          );
          _fetchTickets();
        }
      }
    } catch (e) {
      debugPrint("Error submitting ticket: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit ticket: $e'), backgroundColor: TerraTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedCompanyIdProvider, (previous, next) {
      _fetchTickets();
    });

    ref.watch(availableCompaniesProvider);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: TerraTheme.cream50,
        body: Center(child: CircularProgressIndicator(color: TerraTheme.gold500)),
      );
    }

    final proName = _company?['assigned_pro'] ?? 'Your PRO Agent';

    return Scaffold(
      backgroundColor: TerraTheme.cream50,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            shadowColor: const Color(0x143D4A2A),
            surfaceTintColor: Colors.transparent,
            pinned: true,
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A3D4A2A), blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: SvgPicture.asset(
                    'assets/images/Amanah.svg',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Amanah',
                    style: GoogleFonts.nunitoSans(
                      color: TerraTheme.olive900,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    )),
              ],
            ),
            actions: [
              const NotificationBell(),
              const SizedBox(width: 4),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CompanySelectorChip(),

                  // ── Hero Banner ───────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 180,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [TerraTheme.olive900, Color(0xff4a7c59)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(child: _DotPatternPainterWidget()),
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('Our PRO team is ready\nto assist you.',
                                    style: GoogleFonts.nunitoSans(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      height: 1.3,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Call Concierge CTA
                  ElevatedButton.icon(
                    onPressed: _launchCall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TerraTheme.gold500,
                      foregroundColor: TerraTheme.charcoal800,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.headset_mic_outlined, size: 20),
                    label: Text('Call Concierge',
                        style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),

                  const SizedBox(height: 28),

                  // ── Support Channels ──────────────────────────────
                  Text('Support Channels',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TerraTheme.olive900,
                      )),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      _ChannelCard(
                        icon: Icons.chat_outlined,
                        iconBg: const Color(0x1A10B981),
                        iconColor: TerraTheme.success,
                        label: 'WhatsApp Support',
                        onTap: _launchWhatsApp,
                      ),
                      _ChannelCard(
                        icon: Icons.event_available_outlined,
                        iconBg: const Color(0x1A316342),
                        iconColor: TerraTheme.primary,
                        label: 'Book Meeting',
                        onTap: () {},
                      ),
                      _ChannelCard(
                        icon: Icons.autorenew_outlined,
                        iconBg: const Color(0x1AC9A227),
                        iconColor: TerraTheme.gold500,
                        label: 'Raise Renewal',
                        onTap: _navigateToRaiseRenewal,
                      ),
                      _ChannelCard(
                        icon: Icons.emergency_outlined,
                        iconBg: const Color(0x1AC0392B),
                        iconColor: TerraTheme.error,
                        label: 'Emergency Support',
                        onTap: _launchCall,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── PRO Agent Banner (if assigned) ────────────────
                  if (_company != null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: TerraTheme.olive100,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: TerraTheme.olive100),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: TerraTheme.gold200,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_outline, color: TerraTheme.olive900, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your Assigned PRO',
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TerraTheme.neutral500,
                                      letterSpacing: 0.5,
                                    )),
                                Text(proName,
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: TerraTheme.olive900,
                                    )),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _launchCall,
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: TerraTheme.gold500,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.call_outlined, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 28),

                  // ── Location & Hours ──────────────────────────────
                  // ── FAQ Accordion ─────────────────────────────────
                  Text('Common Questions',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TerraTheme.olive900,
                      )),
                  const SizedBox(height: 14),
                  ...List.generate(_faqs.length, (i) {
                    final faq = _faqs[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _faqExpanded[i] = !_faqExpanded[i]),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [BoxShadow(color: Color(0x0A3D4A2A), blurRadius: 12)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(faq['q']!,
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: TerraTheme.olive900,
                                        )),
                                  ),
                                  AnimatedRotation(
                                    turns: _faqExpanded[i] ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 200),
                                    child: const Icon(Icons.expand_more, color: TerraTheme.neutral500),
                                  ),
                                ],
                              ),
                              AnimatedCrossFade(
                                firstChild: const SizedBox.shrink(),
                                secondChild: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Divider(color: TerraTheme.olive100, height: 1),
                                      const SizedBox(height: 12),
                                      Text(faq['a']!,
                                          style: GoogleFonts.nunitoSans(
                                            fontSize: 13,
                                            color: TerraTheme.neutral500,
                                            height: 1.5,
                                          )),
                                    ],
                                  ),
                                ),
                                crossFadeState: _faqExpanded[i]
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                duration: const Duration(milliseconds: 250),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 28),

                  // ── Submit Ticket Form ────────────────────────────
                  Text('Submit a Ticket',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TerraTheme.olive900,
                      )),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [BoxShadow(color: Color(0x0A3D4A2A), blurRadius: 16, offset: Offset(0, 4))],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _subjectController,
                            style: GoogleFonts.nunitoSans(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Subject',
                              hintStyle: GoogleFonts.nunitoSans(color: TerraTheme.neutral500),
                              filled: true,
                              fillColor: TerraTheme.olive100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Enter a subject' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _messageController,
                            style: GoogleFonts.nunitoSans(fontSize: 14),
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Describe your issue...',
                              hintStyle: GoogleFonts.nunitoSans(color: TerraTheme.neutral500),
                              filled: true,
                              fillColor: TerraTheme.olive100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Enter a message' : null,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submitTicket,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TerraTheme.gold500,
                                foregroundColor: TerraTheme.charcoal800,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                elevation: 0,
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: TerraTheme.charcoal800))
                                  : Text('Submit Ticket',
                                      style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Recent Tickets ────────────────────────────────
                  if (_tickets.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text('Your Tickets',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: TerraTheme.olive900,
                        )),
                    const SizedBox(height: 14),
                    ..._tickets.take(5).map((ticket) {
                      final status = ticket['status'] ?? 'open';
                      final isOpen = status == 'open';
                      final statusColor = isOpen ? TerraTheme.warning : TerraTheme.primary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: TerraTheme.olive100),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ticket['subject'] ?? 'Ticket',
                                        style: GoogleFonts.nunitoSans(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: TerraTheme.olive900,
                                        )),
                                    const SizedBox(height: 2),
                                    Text(ticket['message'] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 12,
                                          color: TerraTheme.neutral500,
                                        )),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text(status.toUpperCase(),
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    )),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Channel Card ───────────────────────────────────────────────────────────────
class _ChannelCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.icon, required this.iconBg, required this.iconColor,
    required this.label, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x0A3D4A2A), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TerraTheme.olive900,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Location Row ───────────────────────────────────────────────────────────────
class _LocationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LocationRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: TerraTheme.olive100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: TerraTheme.olive900, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14, fontWeight: FontWeight.w700, color: TerraTheme.olive900)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: GoogleFonts.nunitoSans(fontSize: 13, color: TerraTheme.neutral500, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dot Pattern Widget ─────────────────────────────────────────────────────────
class _DotPatternPainterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DotPatternPainter());
  }
}

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
