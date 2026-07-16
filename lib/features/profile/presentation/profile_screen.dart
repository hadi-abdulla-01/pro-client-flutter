import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _company;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final res = await supabase
          .from('users')
          .select('*, companies(*), roles(name)')
          .eq('id', userId)
          .single();

      _userProfile = res;
      _company = res['companies'];
    } catch (e) {
      debugPrint("Error loading profile: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    await supabase.auth.signOut();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xff316342)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
                child: Text('PR',
                    style: GoogleFonts.nunitoSans(
                      color: TerraTheme.gold500,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    )),
              ),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Company Card Overview
            if (_company?['entity_type'] != 'individual') ...[
              Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: const Color(0xffe8ecde),
                      child: Text(
                        (_company?['name'] ?? 'C')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xff316342),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _company?['name'] ?? 'Company Name',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xff316342).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (_company?['subscription_plan'] ?? 'Standard').toString().toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xff316342),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ],
            const SizedBox(height: 20),

            // Account details section
            const Text(
              'User Representative Profile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff2b2b26)),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person, color: Color(0xff6b7a4c)),
                      title: const Text('Full Name', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                      subtitle: Text(_userProfile?['name'] ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.email, color: Color(0xff6b7a4c)),
                      title: const Text('Email Address', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                      subtitle: Text(_userProfile?['email'] ?? 'Email', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.security, color: Color(0xff6b7a4c)),
                      title: const Text('Security Authorization', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                      subtitle: Text("Role: ${(_userProfile?['roles']['name'] ?? 'client').toString().toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Company/Family details section
            Text(
              _company?['entity_type'] == 'individual' ? 'Family Profile Details' : 'Company Profile Details',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff2b2b26)),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (_company?['entity_type'] != 'individual') ...[
                      ListTile(
                        leading: const Icon(Icons.badge, color: Color(0xff6b7a4c)),
                        title: const Text('Trade License Number', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                        subtitle: Text(_company?['trade_license_number'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.date_range, color: Color(0xff6b7a4c)),
                        title: const Text('Trade License Issue Date', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                        subtitle: Text(_company?['trade_license_issue'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.event_busy, color: Color(0xff6b7a4c)),
                        title: const Text('Trade License Expiry Date', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                        subtitle: Text(_company?['trade_license_expiry'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.percent, color: Color(0xff6b7a4c)),
                        title: const Text('VAT Number', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                        subtitle: Text(_company?['vat_number'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(Icons.support_agent, color: Color(0xff6b7a4c)),
                      title: const Text('Assigned PRO Agent', style: TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                      subtitle: Text(_company?['assigned_pro'] ?? 'Unassigned', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.contact_mail, color: Color(0xff6b7a4c)),
                      title: Text(_company?['entity_type'] == 'individual' ? 'Primary Email Address' : 'Company Email Address', style: const TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                      subtitle: Text(_company?['email'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.contact_phone, color: Color(0xff6b7a4c)),
                      title: Text(_company?['entity_type'] == 'individual' ? 'Primary Phone Number' : 'Company Phone Number', style: const TextStyle(fontSize: 11, color: Color(0xff8a8a80))),
                      subtitle: Text(_company?['phone'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Sign out button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xffc0392b),
              ),
              onPressed: _handleSignOut,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Sign Out Representative'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
