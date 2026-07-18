import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/company_selector_chip.dart';
import '../../../core/selected_company_provider.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import '../../../core/router.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _employees = [];
  int _expiredDocCount = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchEmployees() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);

      if (companies.isEmpty) {
        _employees = [];
        return;
      }

      List<String> targetCompanyIds = [];
      if (selectedId != null) {
        targetCompanyIds = [selectedId];
      } else {
        targetCompanyIds = companies.map((c) => c['id'] as String).toList();
      }

      if (targetCompanyIds.isNotEmpty) {
        final res = await supabase
            .from('employees')
            .select('*')
            .inFilter('company_id', targetCompanyIds)
            .order('first_name');
        _employees = List<Map<String, dynamic>>.from(res);

        // Determine doc health for each employee
        if (_employees.isNotEmpty) {
          final empIds = _employees.map((e) => e['id']).toList();
          final now = DateTime.now();

          // Fetch all employee documents with expiry dates
          final docsRes = await supabase
              .from('employee_documents')
              .select('id, employee_id, expiry_date')
              .inFilter('employee_id', empIds);
          final docs = docsRes as List;

          // Count total expired
          final expiredDocs = docs.where((d) {
            final exp = d['expiry_date'];
            if (exp == null) return false;
            final expDate = DateTime.tryParse(exp.toString());
            return expDate != null && expDate.isBefore(now);
          }).toList();
          _expiredDocCount = expiredDocs.length;

          // Per-employee: has_expired, has_expiring_soon
          final empExpired = <dynamic, bool>{};
          final empExpiringSoon = <dynamic, bool>{};
          final empHasDocs = <dynamic, bool>{};

          for (final emp in _employees) {
            empExpired[emp['id']] = false;
            empExpiringSoon[emp['id']] = false;
            empHasDocs[emp['id']] = false;
          }

          for (final d in docs) {
            final eid = d['employee_id'];
            final exp = d['expiry_date'];
            if (exp == null) continue;
            empHasDocs[eid] = true;
            final expDate = DateTime.tryParse(exp.toString());
            if (expDate == null) continue;
            if (expDate.isBefore(now)) {
              empExpired[eid] = true;
            } else if (expDate.isBefore(now.add(const Duration(days: 30)))) {
              empExpiringSoon[eid] = true;
            }
          }

          for (final emp in _employees) {
            final id = emp['id'];
            if (empExpired[id] == true) {
              emp['doc_status'] = 'expired'; // red
            } else if (empExpiringSoon[id] == true) {
              emp['doc_status'] = 'expiring_soon'; // orange
            } else if (empHasDocs[id] == true) {
              emp['doc_status'] = 'good'; // green
            } else {
              emp['doc_status'] = 'no_docs'; // no dot
            }
          }
        } else {
          _expiredDocCount = 0;
        }
      }
    } catch (e) {
      debugPrint("Error fetching employees: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Returns the dot color based on doc_status
  Color? _statusDotColor(String? status) {
    switch (status) {
      case 'expired':
        return const Color(0xffc0392b); // red
      case 'expiring_soon':
        return const Color(0xffe67e22); // orange
      case 'good':
        return const Color(0xff27ae60); // green
      default:
        return null; // no dot
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedCompanyIdProvider, (previous, next) {
      setState(() => _isLoading = true);
      _fetchEmployees();
    });

    ref.watch(availableCompaniesProvider);
    final isIndividual = ref.watch(isIndividualProvider);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: TerraTheme.cream50,
        body: Center(
          child: CircularProgressIndicator(color: TerraTheme.gold500),
        ),
      );
    }

    final filtered = _employees.where((emp) {
      final name = "${emp['first_name']} ${emp['last_name']}".toLowerCase();
      final title = (emp['designation'] ?? '').toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          title.contains(_searchQuery.toLowerCase());
    }).toList();

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
                Text(
                  'PRO Services',
                  style: GoogleFonts.nunitoSans(
                    color: TerraTheme.olive900,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            actions: [const NotificationBell(), const SizedBox(width: 4)],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CompanySelectorChip(),
                  // ── Search bar ─────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: TerraTheme.olive100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.nunitoSans(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: isIndividual
                            ? 'Search family members...'
                            : 'Search employees, ID or status...',
                        hintStyle: GoogleFonts.nunitoSans(
                          color: TerraTheme.neutral500,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: TerraTheme.neutral500,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Summary grid ───────────────────────────────
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.group_outlined,
                            iconBg: TerraTheme.olive100,
                            iconColor: TerraTheme.olive900,
                            label: isIndividual
                                ? 'Total Members'
                                : 'Total Personnel',
                            value: '${_employees.length}',
                            valueColor: TerraTheme.olive900,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.priority_high_rounded,
                            iconBg: const Color(0xFFFFD9DD),
                            iconColor: const Color(0xff834751),
                            label: isIndividual
                                ? 'Docs Expired'
                                : 'Documents Expired',
                            value:
                                '${_expiredDocCount.toString().padLeft(2, '0')}',
                            valueColor: const Color(0xff834751),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Section heading ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isIndividual ? 'Family Members' : 'Employees',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: TerraTheme.olive900,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: Row(
                          children: [
                            Text(
                              'Filter',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: TerraTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.tune_rounded,
                              color: TerraTheme.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          // ── Employee list ─────────────────────────────────────────
          filtered.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Text(
                      isIndividual
                          ? 'No family members found.'
                          : 'No employees found.',
                      style: GoogleFonts.nunitoSans(
                        color: TerraTheme.neutral500,
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final emp = filtered[i];
                      final firstName = emp['first_name'] ?? '';
                      final lastName = emp['last_name'] ?? '';
                      final initials =
                          '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
                              .toUpperCase();
                      final dotColor = _statusDotColor(emp['doc_status']);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () => context.go('/employees/${emp['id']}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: TerraTheme.olive100),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A3D4A2A),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Avatar with status dot overlay
                                Stack(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: TerraTheme.olive100,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x1A000000),
                                            blurRadius: 4,
                                          ),
                                        ],
                                        image:
                                            (emp['photo_url'] != null &&
                                                emp['photo_url']
                                                    .toString()
                                                    .isNotEmpty)
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                  emp['photo_url'],
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child:
                                          (emp['photo_url'] == null ||
                                              emp['photo_url']
                                                  .toString()
                                                  .isEmpty)
                                          ? Center(
                                              child: Text(
                                                initials,
                                                style: GoogleFonts.nunitoSans(
                                                  color: TerraTheme.primary,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                    // Status dot at bottom-right of avatar
                                    if (dotColor != null)
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: dotColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                // Name & role
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$firstName $lastName',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: TerraTheme.olive900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        emp['designation'] ??
                                            (isIndividual
                                                ? 'Family Member'
                                                : 'Employee'),
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 13,
                                          color: TerraTheme.neutral500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: TerraTheme.neutral500,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: filtered.length),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TerraTheme.olive100),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A3D4A2A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 13,
              color: TerraTheme.neutral500,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.nunitoSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
