import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import '../../../core/selected_company_provider.dart';

class ActionRequiredScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> alerts;

  const ActionRequiredScreen({super.key, required this.alerts});

  @override
  ConsumerState<ActionRequiredScreen> createState() => _ActionRequiredScreenState();
}

class _ActionRequiredScreenState extends ConsumerState<ActionRequiredScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRenewals();
  }

  Future<void> _fetchRenewals() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);
      List<String> targetCompanyIds = [];
      if (selectedId != null) {
        targetCompanyIds = [selectedId];
      } else {
        targetCompanyIds = companies.map((c) => c['id'] as String).toList();
      }

      if (targetCompanyIds.isNotEmpty) {
        final renewalsRes = await supabase
            .from('renewal_requests')
            .select('id, employee_id, document_category_id, status')
            .inFilter('company_id', targetCompanyIds)
            .inFilter('status', ['pending', 'requested', 'in_progress']);

        for (var alert in widget.alerts) {
          final doc = alert['doc'];
          if (doc != null) {
            Map<String, dynamic>? activeRenewal;
            for (var r in renewalsRes) {
              if (r['document_category_id'] == doc['category_id'] &&
                  r['employee_id'] == doc['employee_id']) {
                final status = r['status'];
                if (status == 'pending' || status == 'requested' || status == 'in_progress') {
                  activeRenewal = r;
                  break;
                }
              }
            }
            setState(() {
              alert['renewalStatus'] = activeRenewal != null ? activeRenewal['status'] : null;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading active renewals: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitRenewRequest(Map<String, dynamic> alert) async {
    try {
      final doc = alert['doc'];
      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);
      final companyId = selectedId ?? (companies.isNotEmpty ? companies.first['id'] : null);

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
    final companies = ref.watch(availableCompaniesProvider);
    final selectedId = ref.watch(selectedCompanyIdProvider);
    final activeCompany = selectedId != null
        ? companies.firstWhere((c) => c['id'] == selectedId, orElse: () => <String, dynamic>{})
        : <String, dynamic>{};
    final logoUrl = activeCompany['logo_url'];

    return Scaffold(
      backgroundColor: TerraTheme.cream50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TerraTheme.olive900),
          onPressed: () => context.pop(),
        ),
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
            Text('Action Required',
                style: GoogleFonts.nunitoSans(
                  color: TerraTheme.olive900,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                )),
          ],
        ),
      ),
      body: widget.alerts.isEmpty
          ? Center(
              child: Text(
                'No action required at this time.',
                style: GoogleFonts.nunitoSans(fontSize: 16, color: TerraTheme.neutral500),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchRenewals,
              color: TerraTheme.primary,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: widget.alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final alert = widget.alerts[i];
                  final isExpired = alert['status'] == 'expired';
                  
                  final statusColor = isExpired ? TerraTheme.error : TerraTheme.warning;
                  final statusLabel = isExpired ? 'EXPIRED' : 'EXPIRING SOON';

                  return Container(
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: TerraTheme.olive900,
                            )),
                        const SizedBox(height: 4),
                        Text(alert['owner'] ?? '',
                            style: GoogleFonts.nunitoSans(fontSize: 14, color: TerraTheme.neutral500)),
                        if (alert['daysLeft'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            isExpired 
                                ? 'Expired ${alert['daysLeft'].abs()} days ago'
                                : 'Expires in ${alert['daysLeft']} days',
                            style: GoogleFonts.nunitoSans(fontSize: 14, color: statusColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Builder(
                          builder: (context) {
                            final renewalStatus = alert['renewalStatus'];
                            final hasActiveRequest = renewalStatus != null;
                            
                            String buttonText = 'Renew Request';
                            Color buttonBgColor = TerraTheme.primary;
                            Color buttonTextColor = Colors.white;
                            
                            if (renewalStatus == 'pending' || renewalStatus == 'requested') {
                              buttonText = 'Requested';
                              buttonBgColor = TerraTheme.neutral500.withOpacity(0.12);
                              buttonTextColor = TerraTheme.neutral500;
                            } else if (renewalStatus == 'in_progress') {
                              buttonText = 'In Progress';
                              buttonBgColor = TerraTheme.gold500.withOpacity(0.15);
                              buttonTextColor = TerraTheme.gold500;
                            }

                            return SizedBox(
                              width: double.infinity,
                              height: 36,
                              child: ElevatedButton(
                                onPressed: hasActiveRequest ? null : () => _submitRenewRequest(alert),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: buttonBgColor,
                                  foregroundColor: buttonTextColor,
                                  disabledBackgroundColor: buttonBgColor,
                                  disabledForegroundColor: buttonTextColor,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  buttonText,
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
