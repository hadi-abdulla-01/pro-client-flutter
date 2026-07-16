import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'selected_company_provider.dart';
import 'theme.dart';

class CompanySelectorChip extends ConsumerWidget {
  const CompanySelectorChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(availableCompaniesProvider);
    final selectedId = ref.watch(selectedCompanyIdProvider);

    if (companies.length <= 1) {
      return const SizedBox.shrink(); // Standalone company: hide selector
    }

    final activeCompany = companies.firstWhere(
      (c) => c['id'] == selectedId,
      orElse: () => {'name': 'All Companies'},
    );
    final String labelName = selectedId == null ? 'All Companies' : activeCompany['name'];

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
      child: UnconstrainedBox(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => _showCompanySelector(context, ref, companies, selectedId),
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: TerraTheme.olive100,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: TerraTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.corporate_fare, size: 16, color: TerraTheme.primary),
                const SizedBox(width: 8),
                Text(
                  labelName,
                  style: GoogleFonts.nunitoSans(
                    color: TerraTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: TerraTheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCompanySelector(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> companies, String? selectedId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: TerraTheme.cream50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: TerraTheme.olive100,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Select Company',
              style: GoogleFonts.nunitoSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: TerraTheme.olive900,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Option: All Companies
                  ListTile(
                    leading: const Icon(Icons.grid_view_rounded, color: TerraTheme.primary),
                    title: Text(
                      'All Companies (Combined View)',
                      style: GoogleFonts.nunitoSans(
                        fontWeight: selectedId == null ? FontWeight.w800 : FontWeight.w600,
                        color: selectedId == null ? TerraTheme.primary : TerraTheme.olive900,
                      ),
                    ),
                    trailing: selectedId == null ? const Icon(Icons.check_circle, color: TerraTheme.primary) : null,
                    onTap: () {
                      ref.read(selectedCompanyIdProvider.notifier).state = null;
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(color: TerraTheme.olive100),
                  // List of companies in group
                  ...companies.map((co) {
                    final isSelected = co['id'] == selectedId;
                    return ListTile(
                      leading: const Icon(Icons.corporate_fare, color: TerraTheme.primary),
                      title: Text(
                        co['name'],
                        style: GoogleFonts.nunitoSans(
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? TerraTheme.primary : TerraTheme.olive900,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: TerraTheme.primary) : null,
                      onTap: () {
                        ref.read(selectedCompanyIdProvider.notifier).state = co['id'];
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
