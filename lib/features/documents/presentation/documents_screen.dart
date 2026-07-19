import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/company_selector_chip.dart';
import '../../../core/selected_company_provider.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/router.dart';
import 'document_viewer_screen.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _isLoading = true;
  String?
  _selectedCategoryGroup; // null = 'All Docs', 'company'|'partner'|'employee' (corporate) or 'family'|'relative' (individual)
  String _searchQuery = '';
  String _selectedPartnerOwner = 'all';
  List<Map<String, dynamic>> _documents = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final isIndividual = ref.read(isIndividualProvider);
    if (isIndividual) {
      _selectedCategoryGroup = 'family';
    } else {
      _selectedCategoryGroup = 'company';
    }
    _fetchDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDocuments() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final companies = ref.read(availableCompaniesProvider);
      final selectedId = ref.read(selectedCompanyIdProvider);

      if (companies.isEmpty) {
        _documents = [];
        return;
      }

      List<String> targetCompanyIds = [];
      if (selectedId != null) {
        targetCompanyIds = [selectedId];
      } else {
        targetCompanyIds = companies.map((c) => c['id'] as String).toList();
      }

      if (targetCompanyIds.isNotEmpty) {
        final compDocsRes = await supabase
            .from('company_documents')
            .select('*, document_categories(*)')
            .inFilter('company_id', targetCompanyIds);
        final List compDocs = compDocsRes;

        final employeesRes = await supabase
            .from('employees')
            .select('id')
            .inFilter('company_id', targetCompanyIds);
        final empIds = List.from(employeesRes).map((e) => e['id']).toList();

        List empDocs = [];
        if (empIds.isNotEmpty) {
          final empDocsRes = await supabase
              .from('employee_documents')
              .select(
                '*, employees(first_name, last_name), document_categories(*)',
              )
              .inFilter('employee_id', empIds);
          empDocs = empDocsRes;
        }

        _documents = [];
        for (var doc in compDocs) {
          // Use category_group from DB directly — no keyword guessing needed
          final group =
              (doc['document_categories']?['category_group'] ?? 'company')
                  .toString();
          _documents.add({
            'id': doc['id'],
            'name': doc['file_name'],
            'category': doc['document_categories']['name'],
            'categoryId': doc['document_categories']['id'],
            'categoryCode': doc['document_categories']['code'],
            'owner': 'Company Level',
            'expiry': doc['expiry_date'],
            'issue': doc['issue_date'],
            'size': doc['size_bytes'],
            'path': doc['file_path'],
            'bucket': 'company-docs',
            'groupType': group, // 'company' | 'partner' | 'family'
            'ownerName': doc['owner_name'],
          });
        }
        for (var doc in empDocs) {
          final empName = doc['employees'] != null
              ? "${doc['employees']['first_name']} ${doc['employees']['last_name']}"
              : 'Employee Level';
          final group =
              (doc['document_categories']?['category_group'] ?? 'employee')
                  .toString();
          _documents.add({
            'id': doc['id'],
            'name': doc['file_name'],
            'category': doc['document_categories']['name'],
            'categoryId': doc['document_categories']['id'],
            'categoryCode': doc['document_categories']['code'],
            'owner': empName,
            'expiry': doc['expiry_date'],
            'issue': doc['issue_date'],
            'size': doc['size_bytes'],
            'path': doc['file_path'],
            'bucket': 'employee-docs',
            'groupType': group, // 'employee' | 'relative'
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading documents: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleView(Map<String, dynamic> doc) async {
    try {
      final String signedUrl = await supabase.storage
          .from(doc['bucket'])
          .createSignedUrl(doc['path'], 300);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DocumentViewerScreen(
              url: signedUrl,
              fileName: doc['name'] ?? 'Document',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to view document: $e'),
            backgroundColor: TerraTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDownload(Map<String, dynamic> doc) async {
    try {
      // Show downloading message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading ${doc['name'] ?? 'document'}...'),
            backgroundColor: TerraTheme.primary,
            duration: const Duration(seconds: 1),
          ),
        );
      }

      final String signedUrl = await supabase.storage
          .from(doc['bucket'])
          .createSignedUrl(doc['path'], 300);
      final extension = await FileUtils.getFileExtension(
        doc['name'] as String? ?? 'file',
      );

      final Directory saveDir = Platform.isAndroid
          ? Directory('/storage/emulated/0/Download/ProApp')
          : await getApplicationDocumentsDirectory();

      await saveDir.create(recursive: true);

      final String fileName =
          "${doc['name'] ?? 'doc'}_${DateTime.now().millisecondsSinceEpoch}.$extension";
      final String savePath = "${saveDir.path}/$fileName";

      await Dio().download(signedUrl, savePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved to: ProApp Folder in Downloads'),
            backgroundColor: TerraTheme.primary,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading document: $e'),
            backgroundColor: TerraTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleShare(Map<String, dynamic> doc) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preparing ${doc['name'] ?? 'document'} to share...'),
            backgroundColor: TerraTheme.primary,
            duration: const Duration(seconds: 1),
          ),
        );
      }

      final String signedUrl = await supabase.storage
          .from(doc['bucket'])
          .createSignedUrl(doc['path'], 300);
      final extension = await FileUtils.getFileExtension(
        doc['name'] as String? ?? 'file',
      );

      // Download to a temp file preserving format
      final tempDir = await getTemporaryDirectory();
      final fileName =
          '${doc['name'] ?? 'document'}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final savePath = '${tempDir.path}/$fileName';
      await Dio().download(signedUrl, savePath);

      final mimeType = FileUtils.getMimeType(extension);

      await Share.shareXFiles([
        XFile(savePath, mimeType: mimeType),
      ], subject: doc['name'] ?? 'Document');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing document: $e'),
            backgroundColor: TerraTheme.error,
          ),
        );
      }
    }
  }

  String _docStatusLabel(Map<String, dynamic> doc) {
    final expiryStr = doc['expiry'];
    if (expiryStr == null) return 'Active';
    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null) return 'Active';
    final now = DateTime.now();
    if (expiry.isBefore(now)) return 'Expired';
    if (expiry.isBefore(now.add(const Duration(days: 30))))
      return 'Expiring Soon';
    return 'Active';
  }

  Color _docStatusColor(String status) {
    switch (status) {
      case 'Expired':
        return TerraTheme.error;
      case 'Expiring Soon':
        return TerraTheme.warning;
      default:
        return TerraTheme.success;
    }
  }

  IconData _categoryIcon(String? code) {
    switch (code) {
      case 'TRADE_LIC':
        return Icons.description_outlined;
      case 'MOA':
        return Icons.gavel_outlined;
      case 'VAT':
        return Icons.account_balance_outlined;
      case 'EST_CARD':
        return Icons.folder_shared_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  void _showDocDetails(Map<String, dynamic> doc) {
    final status = _docStatusLabel(doc);
    final statusColor = _docStatusColor(status);
    final isIndiv = ref.read(isIndividualProvider);
    final ownerDisplay = doc['owner'] == 'Company Level'
        ? (isIndiv ? 'Family Level' : 'Company Level')
        : (doc['owner'] == 'Employee Level'
              ? (isIndiv ? 'Relative Level' : 'Employee Level')
              : doc['owner']);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: TerraTheme.cream50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: TerraTheme.olive100,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: TerraTheme.olive100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _categoryIcon(doc['categoryCode']),
                color: TerraTheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              doc['name'] ?? 'Document',
              style: GoogleFonts.nunitoSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: TerraTheme.olive900,
              ),
            ),
            Text(
              '${doc['category']} · $ownerDisplay',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: TerraTheme.neutral500,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TerraTheme.olive100),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Status',
                    value: status,
                    valueColor: statusColor,
                  ),
                  if (doc['issue'] != null) ...[
                    const Divider(height: 20, color: TerraTheme.olive100),
                    _DetailRow(label: 'Issue Date', value: doc['issue']),
                  ],
                  const Divider(height: 20, color: TerraTheme.olive100),
                  _DetailRow(
                    label: 'Expiry Date',
                    value: doc['expiry'] ?? 'Permanent (No Expiry)',
                    valueColor: doc['expiry'] == null
                        ? TerraTheme.primary
                        : null,
                  ),
                  if (doc['size'] != null) ...[
                    const Divider(height: 20, color: TerraTheme.olive100),
                    _DetailRow(
                      label: 'File Size',
                      value:
                          '${((doc['size'] as int) / (1024 * 1024)).toStringAsFixed(2)} MB',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _handleView(doc);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TerraTheme.olive900,
                      side: const BorderSide(color: TerraTheme.olive100),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(
                      'View',
                      style: GoogleFonts.nunitoSans(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _handleDownload(doc);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TerraTheme.gold500,
                      foregroundColor: TerraTheme.charcoal800,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'Download',
                      style: GoogleFonts.nunitoSans(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: TerraTheme.olive100,
                  borderRadius: BorderRadius.circular(50),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _handleShare(doc);
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(
                        Icons.share_rounded,
                        size: 20,
                        color: TerraTheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build a document card widget (reused inside sections)
  Widget _buildDocCard(Map<String, dynamic> doc) {
    final status = _docStatusLabel(doc);
    final statusColor = _docStatusColor(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x1A3D4A2A)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A3D4A2A),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: TerraTheme.olive100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _categoryIcon(doc['categoryCode']),
                      color: TerraTheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc['name'] ?? 'Document',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TerraTheme.olive900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          doc['expiry'] != null
                              ? 'Exp: ${doc['expiry']}'
                              : 'No Expiry',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            color: TerraTheme.neutral500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            status,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: TerraTheme.olive100),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDocDetails(doc),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TerraTheme.olive900,
                        side: BorderSide.none,
                        backgroundColor: TerraTheme.olive100,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: Text(
                        'View',
                        style: GoogleFonts.nunitoSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleDownload(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TerraTheme.gold500,
                        foregroundColor: TerraTheme.charcoal800,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        'Download',
                        style: GoogleFonts.nunitoSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: TerraTheme.olive100,
                    borderRadius: BorderRadius.circular(50),
                    child: InkWell(
                      onTap: () => _handleShare(doc),
                      borderRadius: BorderRadius.circular(50),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.share_rounded,
                          size: 18,
                          color: TerraTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(selectedCompanyIdProvider, (previous, next) {
      _fetchDocuments();
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

    // Filter logic
    final displayedDocs = _documents.where((doc) {
      final group = doc['groupType'] as String? ?? '';
      // When "All Docs" is selected (null), exclude employee docs for both account types
      if (_selectedCategoryGroup == null && group == 'employee') return false;
      final matchCat =
          _selectedCategoryGroup == null || group == _selectedCategoryGroup;
      final matchPartner =
          _selectedCategoryGroup != 'partner' ||
          _selectedPartnerOwner == 'all' ||
          doc['ownerName'] == _selectedPartnerOwner;
      final matchSearch =
          _searchQuery.isEmpty ||
          (doc['name'] ?? '').toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );
      return matchCat && matchPartner && matchSearch;
    }).toList();

    // Get sorted list of partner owner names
    final partnerOwnerOptions = <String>{};
    for (final doc in _documents) {
      if (doc['groupType'] == 'partner' &&
          doc['ownerName'] != null &&
          doc['ownerName'].toString().isNotEmpty) {
        partnerOwnerOptions.add(doc['ownerName'].toString());
      }
    }
    final sortedPartnerOwners = partnerOwnerOptions.toList()..sort();

    // Group partner docs by owner for the "All Partners" view
    Map<String, List<Map<String, dynamic>>> partnerSections = {};
    if (_selectedCategoryGroup == 'partner') {
      for (final doc in displayedDocs) {
        final owner = doc['ownerName']?.toString() ?? 'Unknown';
        partnerSections.putIfAbsent(owner, () => []);
        if (_selectedPartnerOwner == 'all') {
          partnerSections[owner]!.add(doc);
        }
      }
    }

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
                Text(
                  'Amanah',
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
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documents',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: TerraTheme.olive900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isIndividual
                        ? 'Secure access to your personal and family legal records.'
                        : 'Secure access to your corporate legal records.',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      color: TerraTheme.neutral500,
                    ),
                  ),
                  const CompanySelectorChip(),

                  const SizedBox(height: 20),

                  // ── Category chips ─────────────────────────────
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (isIndividual) ...[
                          _CategoryChip(
                            label: 'My Documents',
                            isSelected: _selectedCategoryGroup == 'family',
                            onTap: () => setState(
                              () => _selectedCategoryGroup = 'family',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CategoryChip(
                            label: 'Family Documents',
                            isSelected: _selectedCategoryGroup == 'relative',
                            onTap: () => setState(
                              () => _selectedCategoryGroup = 'relative',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CategoryChip(
                            label: 'All Docs',
                            isSelected: _selectedCategoryGroup == null,
                            onTap: () =>
                                setState(() => _selectedCategoryGroup = null),
                          ),
                        ] else ...[
                          _CategoryChip(
                            label: 'Company Docs',
                            isSelected: _selectedCategoryGroup == 'company',
                            onTap: () => setState(
                              () => _selectedCategoryGroup = 'company',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CategoryChip(
                            label: 'Partner Docs',
                            isSelected: _selectedCategoryGroup == 'partner',
                            onTap: () {
                              setState(() {
                                _selectedCategoryGroup = 'partner';
                                // Default to first partner owner
                                final firstOwner =
                                    sortedPartnerOwners.isNotEmpty
                                    ? sortedPartnerOwners.first
                                    : 'all';
                                _selectedPartnerOwner = firstOwner;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _CategoryChip(
                            label: 'All Docs',
                            isSelected: _selectedCategoryGroup == null,
                            onTap: () =>
                                setState(() => _selectedCategoryGroup = null),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Search bar ─────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: TerraTheme.olive100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: TerraTheme.charcoal800,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search documents...',
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

                  // ── Partner filter chips (individual first, All Partners last) ──
                  if (!isIndividual && _selectedCategoryGroup == 'partner') ...[
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Individual partners first
                          ...sortedPartnerOwners.map(
                            (owner) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _CategoryChip(
                                label: owner,
                                isSelected: _selectedPartnerOwner == owner,
                                onTap: () => setState(
                                  () => _selectedPartnerOwner = owner,
                                ),
                              ),
                            ),
                          ),
                          // "All Partners" at the end with gold accent
                          _CategoryChip(
                            label: 'All Partners',
                            isSelected: _selectedPartnerOwner == 'all',
                            onTap: () =>
                                setState(() => _selectedPartnerOwner = 'all'),
                            accent: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),

          // ── Document list ─────────────────────────────────────────
          if (displayedDocs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No documents found.',
                  style: GoogleFonts.nunitoSans(color: TerraTheme.neutral500),
                ),
              ),
            )
          else if (_selectedCategoryGroup == 'partner' &&
              _selectedPartnerOwner == 'all')
            // Grouped by partner name
            ...partnerSections.entries.map((entry) {
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Partner section header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: TerraTheme.gold500.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              color: TerraTheme.primary,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            entry.key,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: TerraTheme.olive900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Partner docs
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        children: entry.value.map(_buildDocCard).toList(),
                      ),
                    ),
                  ],
                ),
              );
            })
          else
            // Flat list for non-partner views or single partner view
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final doc = displayedDocs[i];
                  return _buildDocCard(doc);
                }, childCount: displayedDocs.length),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool accent; // For "All Partners" chip

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    // For "All Partners" chip at the end, use accent gold colors when selected
    Color bgColor;
    if (isSelected) {
      bgColor = accent ? TerraTheme.gold500 : TerraTheme.gold200;
    } else {
      bgColor = TerraTheme.olive100;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunitoSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: TerraTheme.olive900,
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.nunitoSans(
            fontSize: 13,
            color: TerraTheme.neutral500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.nunitoSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? TerraTheme.olive900,
          ),
        ),
      ],
    );
  }
}
