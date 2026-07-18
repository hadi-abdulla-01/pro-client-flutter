import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      debugPrint('profile photo_url: ${res['photo_url']}');
      debugPrint('company logo_url: ${res['companies']?['logo_url']}');
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

  Widget _buildProfileAvatar() {
    // Both individual and corporate accounts store their image in companies.logo_url
    // (uploaded via the admin web app to the public-assets bucket)
    final String? imageUrl =
        _company?['logo_url']?.toString().trim().isNotEmpty == true
        ? _company!['logo_url'].toString().trim()
        : null;

    final isIndividual = _company?['entity_type'] == 'individual';
    final String initial = isIndividual
        ? ((_userProfile?['name'] ?? 'U') as String)[0].toUpperCase()
        : ((_company?['name'] ?? 'C') as String)[0].toUpperCase();

    final fallback = CircleAvatar(
      radius: 32,
      backgroundColor: const Color(0xffe8ecde),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xff316342),
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (imageUrl == null) return fallback;

    return ClipOval(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return fallback;
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Avatar image failed to load: $error');
            return fallback;
          },
        ),
      ),
    );
  }

  Future<void> _handleSignOut() async {
    await supabase.auth.signOut();
    if (mounted) {
      context.go('/login');
    }
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isObscureCurrent = true;
    bool isObscureNew = true;
    bool isObscureConfirm = true;
    bool isLoading = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xff316342),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Change Password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff2b2b26),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: TerraTheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: TerraTheme.error.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: TerraTheme.error,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: GoogleFonts.nunitoSans(
                              color: TerraTheme.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: currentPasswordController,
                  obscureText: isObscureCurrent,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xff2b2b26),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: const Color(0xff8a8a80),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Color(0xff8a8a80),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isObscureCurrent
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xff8a8a80),
                      ),
                      onPressed: () =>
                          setState(() => isObscureCurrent = !isObscureCurrent),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: true,
                    fillColor: TerraTheme.cream50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xffe8ecde)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xffe8ecde)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xff316342),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: newPasswordController,
                  obscureText: isObscureNew,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xff2b2b26),
                  ),
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: const Color(0xff8a8a80),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Color(0xff8a8a80),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isObscureNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xff8a8a80),
                      ),
                      onPressed: () =>
                          setState(() => isObscureNew = !isObscureNew),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: true,
                    fillColor: TerraTheme.cream50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xffe8ecde)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xffe8ecde)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xff316342),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: isObscureConfirm,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xff2b2b26),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    labelStyle: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: const Color(0xff8a8a80),
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Color(0xff8a8a80),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isObscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xff8a8a80),
                      ),
                      onPressed: () =>
                          setState(() => isObscureConfirm = !isObscureConfirm),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: true,
                    fillColor: TerraTheme.cream50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xffe8ecde)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xffe8ecde)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xff316342),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Must be 8+ characters with uppercase, lowercase, number, and special character',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      color: const Color(0xff8a8a80),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xff8a8a80),
              ),
              child: Text(
                'Cancel',
                style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
              ),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (newPasswordController.text !=
                          confirmPasswordController.text) {
                        setState(() => errorMessage = 'Passwords do not match');
                        return;
                      }
                      if (newPasswordController.text.length < 8) {
                        setState(
                          () => errorMessage =
                              'Password must be at least 8 characters',
                        );
                        return;
                      }
                      setState(() {
                        isLoading = true;
                        errorMessage = null;
                      });
                      try {
                        await supabase.auth.updateUser(
                          UserAttributes(password: newPasswordController.text),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Password updated successfully',
                                style: GoogleFonts.nunitoSans(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: const Color(0xff316342),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() {
                          errorMessage = e
                              .toString()
                              .replaceAll('Exception: ', '')
                              .replaceAll('AuthException: ', '');
                        });
                      } finally {
                        setState(() => isLoading = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff316342),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'Update Password',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Entity Card Overview
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    _buildProfileAvatar(),
                    const SizedBox(height: 12),
                    Text(
                      _company?['entity_type'] == 'individual'
                          ? (_userProfile?['name'] ?? 'Family Name')
                          : (_company?['name'] ?? 'Company Name'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (_company?['entity_type'] != 'individual')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xff316342).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (_company?['subscription_plan'] ?? 'Standard')
                              .toString()
                              .toUpperCase(),
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
            const SizedBox(height: 20),

            // Account details section
            const Text(
              'User Representative Profile',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xff2b2b26),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.person,
                        color: Color(0xff6b7a4c),
                      ),
                      title: const Text(
                        'Full Name',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff8a8a80),
                        ),
                      ),
                      subtitle: Text(
                        _userProfile?['name'] ?? 'User',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.email,
                        color: Color(0xff6b7a4c),
                      ),
                      title: const Text(
                        'Email Address',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff8a8a80),
                        ),
                      ),
                      subtitle: Text(
                        _userProfile?['email'] ?? 'Email',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.security,
                        color: Color(0xff6b7a4c),
                      ),
                      title: const Text(
                        'Security Authorization',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff8a8a80),
                        ),
                      ),
                      subtitle: Text(
                        "Role: ${(_userProfile?['roles']['name'] ?? 'client').toString().toUpperCase()}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Company/Family details section
            Text(
              _company?['entity_type'] == 'individual'
                  ? 'Family Profile Details'
                  : 'Company Profile Details',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xff2b2b26),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (_company?['entity_type'] != 'individual') ...[
                      ListTile(
                        leading: const Icon(
                          Icons.badge,
                          color: Color(0xff6b7a4c),
                        ),
                        title: const Text(
                          'Trade License Number',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff8a8a80),
                          ),
                        ),
                        subtitle: Text(
                          _company?['trade_license_number'] ?? 'N/A',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.date_range,
                          color: Color(0xff6b7a4c),
                        ),
                        title: const Text(
                          'Trade License Issue Date',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff8a8a80),
                          ),
                        ),
                        subtitle: Text(
                          _company?['trade_license_issue'] ?? 'N/A',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.event_busy,
                          color: Color(0xff6b7a4c),
                        ),
                        title: const Text(
                          'Trade License Expiry Date',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff8a8a80),
                          ),
                        ),
                        subtitle: Text(
                          _company?['trade_license_expiry'] ?? 'N/A',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.percent,
                          color: Color(0xff6b7a4c),
                        ),
                        title: const Text(
                          'VAT Number',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff8a8a80),
                          ),
                        ),
                        subtitle: Text(
                          _company?['vat_number'] ?? 'N/A',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: const Icon(
                        Icons.support_agent,
                        color: Color(0xff6b7a4c),
                      ),
                      title: const Text(
                        'Assigned PRO Agent',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff8a8a80),
                        ),
                      ),
                      subtitle: Text(
                        _company?['assigned_pro'] ?? 'Unassigned',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.contact_mail,
                        color: Color(0xff6b7a4c),
                      ),
                      title: Text(
                        _company?['entity_type'] == 'individual'
                            ? 'Primary Email Address'
                            : 'Company Email Address',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff8a8a80),
                        ),
                      ),
                      subtitle: Text(
                        _company?['email'] ?? 'N/A',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.contact_phone,
                        color: Color(0xff6b7a4c),
                      ),
                      title: Text(
                        _company?['entity_type'] == 'individual'
                            ? 'Primary Phone Number'
                            : 'Company Phone Number',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff8a8a80),
                        ),
                      ),
                      subtitle: Text(
                        _company?['phone'] ?? 'N/A',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Change Password button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: TerraTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _showChangePasswordDialog();
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_reset_rounded),
                  SizedBox(width: 8),
                  Text('Change Password'),
                ],
              ),
            ),
            const SizedBox(height: 12),

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
