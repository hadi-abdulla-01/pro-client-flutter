import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/supabase_client.dart';
import '../../../core/selected_company_provider.dart';
import '../../documents/presentation/document_viewer_screen.dart';

class EmployeeDetailScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _employee;
  List<Map<String, dynamic>> _documents = [];

  @override
  void initState() {
    super.initState();
    _fetchEmployeeDetails();
  }

  Future<void> _fetchEmployeeDetails() async {
    try {
      // Fetch Employee Profile info
      final empRes = await supabase
          .from('employees')
          .select('*')
          .eq('id', widget.employeeId)
          .single();
      _employee = empRes;

      // Fetch Employee Documents linked
      final docsRes = await supabase
          .from('employee_documents')
          .select('*, document_categories(*)')
          .eq('employee_id', widget.employeeId);
      
      _documents = List<Map<String, dynamic>>.from(docsRes);
    } catch (e) {
      debugPrint("Error loading employee details: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _viewDoc(Map<String, dynamic> doc) async {
    try {
      final String path = doc['file_path'];
      final String signedUrl = await supabase.storage
          .from('employee-docs')
          .createSignedUrl(path, 300);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DocumentViewerScreen(
              url: signedUrl,
              fileName: doc['file_name'] ?? 'Document',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to view document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Handle document file download/signed url trigger
  Future<void> _downloadDoc(Map<String, dynamic> doc) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading file: ${doc['file_name']}...'),
            backgroundColor: const Color(0xff316342),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      final String path = doc['file_path'];
      final String signedUrlRes = await supabase.storage
          .from('employee-docs')
          .createSignedUrl(path, 300);
      
      Directory? saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download/ProApp');
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }
      
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      String extension = '';
      if (path.contains('.')) {
        final ext = path.split('.').last.toLowerCase();
        if (['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'doc', 'docx'].contains(ext)) {
          extension = ext;
        }
      }
      if (extension.isEmpty) {
        final typeStr = (doc['file_type'] ?? '').toString().toLowerCase();
        final nameStr = (doc['file_name'] ?? '').toString().toLowerCase();
        if (typeStr.contains('pdf') || nameStr.endsWith('.pdf')) {
          extension = 'pdf';
        } else if (nameStr.endsWith('.png')) {
          extension = 'png';
        } else if (nameStr.endsWith('.jpeg') || nameStr.endsWith('.jpg')) {
          extension = 'jpg';
        }
      }
      if (extension.isEmpty) {
        try {
          final response = await Dio().head(
            signedUrlRes,
            options: Options(
              followRedirects: true,
              validateStatus: (status) => status != null && status < 500,
            ),
          );
          final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
          if (contentType.contains('pdf')) {
            extension = 'pdf';
          } else if (contentType.contains('image/png')) {
            extension = 'png';
          } else if (contentType.contains('image/jpeg') || contentType.contains('image/jpg')) {
            extension = 'jpg';
          } else if (contentType.contains('image/gif')) {
            extension = 'gif';
          } else if (contentType.contains('image/webp')) {
            extension = 'webp';
          }
        } catch (e) {
          debugPrint('HEAD request failed to determine file type for download: $e');
        }
      }
      if (extension.isEmpty) {
        extension = 'jpg';
      }

      final String fileName = "${doc['file_name'] ?? 'doc'}_${DateTime.now().millisecondsSinceEpoch}.$extension";
      final String savePath = "${saveDir.path}/$fileName";

      await Dio().download(signedUrlRes, savePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved to: ProApp Folder in Downloads'),
            backgroundColor: const Color(0xff316342),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDocCard(Map<String, dynamic> doc) {
    final title = doc['document_categories']?['name'] ?? 'Document';
    final number = doc['document_number'];
    final issueDate = doc['issue_date'];
    final expiryDate = doc['expiry_date'];

    final hasExpiry = expiryDate != null;
    bool isExpired = false;
    bool isSoon = false;

    if (hasExpiry) {
      final expDate = DateTime.parse(expiryDate);
      isExpired = expDate.isBefore(DateTime.now());
      isSoon = !isExpired && expDate.isBefore(DateTime.now().add(const Duration(days: 30)));
    }

    final Color statusColor = isExpired
        ? const Color(0xffc0392b)
        : isSoon
            ? const Color(0xfff59e0b)
            : const Color(0xff10b981);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isExpired
                        ? 'EXPIRED'
                        : isSoon
                            ? 'EXPIRING'
                            : 'ACTIVE',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Document ID:', style: TextStyle(color: Color(0xff8a8a80), fontSize: 12)),
                Text(number ?? 'Not provided', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            if (issueDate != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Issue Date:', style: TextStyle(color: Color(0xff8a8a80), fontSize: 12)),
                  Text(
                    issueDate,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xff2b2b26),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Expiry Date:', style: TextStyle(color: Color(0xff8a8a80), fontSize: 12)),
                Text(
                  expiryDate ?? 'No expiry date',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isExpired ? const Color(0xffc0392b) : const Color(0xff2b2b26),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                InkWell(
                  onTap: () => _viewDoc(doc),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility, size: 16, color: Color(0xff316342)),
                      SizedBox(width: 4),
                      Text('View', style: TextStyle(color: Color(0xff316342), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                Container(width: 1, height: 16, color: Colors.grey.shade300),
                InkWell(
                  onTap: () => _downloadDoc(doc),
                  child: const Row(
                    children: [
                      Icon(Icons.download, size: 16, color: Color(0xff316342)),
                      SizedBox(width: 4),
                      Text('Download', style: TextStyle(color: Color(0xff316342), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ],
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

    final isIndividual = ref.watch(isIndividualProvider);

    if (_employee == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            isIndividual ? 'Relative profile not found.' : 'Employee profile not found.', 
            style: const TextStyle(color: Color(0xff8a8a80)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isIndividual ? 'Relative Profile' : 'Employee Profile', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Employee header card
            Card(
              color: const Color(0xff3d4a2a),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xffe8ecde),
                      child: Text(
                        "${_employee!['first_name'][0]}${_employee!['last_name'][0]}".toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xff3d4a2a),
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "${_employee!['first_name']} ${_employee!['last_name']}",
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _employee!['designation'] ?? (isIndividual ? 'Family Member' : 'Employee'),
                      style: const TextStyle(color: Color(0xffbccd98), fontSize: 13),
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Icon(Icons.phone, color: Colors.white70, size: 18),
                            const SizedBox(height: 4),
                            Text(
                              _employee!['phone'] ?? 'N/A',
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Icon(Icons.email, color: Colors.white70, size: 18),
                            const SizedBox(height: 4),
                            Text(
                              _employee!['email'] ?? 'N/A',
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Identity & Residency Documents',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff2b2b26)),
            ),
            const SizedBox(height: 10),

            if (_documents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No documents uploaded yet.', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._documents.map((doc) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: _buildDocCard(doc),
                );
              }),
          ],
        ),
      ),
    );
  }
}

