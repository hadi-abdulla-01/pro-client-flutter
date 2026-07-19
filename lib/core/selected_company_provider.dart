import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'supabase_client.dart';

// The currently selected company ID. 
// Null represents "All Companies" in a group context.
final selectedCompanyIdProvider = StateProvider<String?>((ref) => null);

// List of companies available to the logged-in client user account
final availableCompaniesProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);

// Returns true if the active company is an Individual/Family client
final isIndividualProvider = Provider<bool>((ref) {
  final selectedId = ref.watch(selectedCompanyIdProvider);
  final companies = ref.watch(availableCompaniesProvider);
  if (selectedId == null) {
    return companies.isNotEmpty && companies.any((c) => c['entity_type'] == 'individual');
  }
  final activeCompany = companies.firstWhere(
    (c) => c['id'] == selectedId,
    orElse: () => <String, dynamic>{},
  );
  return activeCompany['entity_type'] == 'individual';
});

// Loading state for fetching user companies list
final companiesLoadingProvider = StateProvider<bool>((ref) => false);

// Whether the current user has been blocked by an admin.
// Defaults to false; set during fetchUserCompanies.
final isBlockedProvider = StateProvider<bool>((ref) => false);

Future<void> fetchUserCompanies(WidgetRef ref) async {
  ref.read(companiesLoadingProvider.notifier).state = true;
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    // Fetch profile — read both `status` (set by the admin webapp) and
    // `is_blocked` (boolean kept in sync). Either one triggers the block gate.
    Map<String, dynamic> profileRes;
    try {
      profileRes = await supabase
          .from('users')
          .select('company_id, group_id, status, is_blocked')
          .eq('id', userId)
          .single();
    } catch (_) {
      // Columns may not exist yet — retry with minimal fields
      profileRes = await supabase
          .from('users')
          .select('company_id, group_id')
          .eq('id', userId)
          .single();
    }

    // Blocked if either field says so
    final blocked =
        profileRes['is_blocked'] == true ||
        profileRes['status'] == 'blocked';
    ref.read(isBlockedProvider.notifier).state = blocked;

    // Always continue loading companies regardless of blocked status.
    // The dashboard will show the blocked banner while still rendering
    // the shell (no data queries run in blocked state).
    final companyId = profileRes['company_id'];
    final groupId = profileRes['group_id'];
    
    List<Map<String, dynamic>> companiesList = [];
    if (groupId != null) {
      // Query companies in this group
      final res = await supabase
          .from('companies')
          .select('*')
          .eq('group_id', groupId)
          .order('name');
      companiesList = List<Map<String, dynamic>>.from(res);
    } else if (companyId != null) {
      // Query single standalone company
      final res = await supabase
          .from('companies')
          .select('*')
          .eq('id', companyId)
          .single();
      companiesList = [Map<String, dynamic>.from(res)];
    }
    
    ref.read(availableCompaniesProvider.notifier).state = companiesList;
    if (companiesList.isNotEmpty) {
      if (companiesList.length > 1) {
        // Multi-company group: Default to "All Companies" (null)
        ref.read(selectedCompanyIdProvider.notifier).state = null;
      } else {
        // Standalone: Default to the only available company
        ref.read(selectedCompanyIdProvider.notifier).state = companiesList.first['id'];
      }
    }
  } catch (e) {
    print("Error loading companies in selected_company_provider: $e");
  } finally {
    ref.read(companiesLoadingProvider.notifier).state = false;
  }
}
