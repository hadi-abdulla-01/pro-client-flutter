import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/supabase_client.dart';
import '../../../core/selected_company_provider.dart';

class RenewalRequestScreen extends ConsumerStatefulWidget {
  const RenewalRequestScreen({super.key});

  @override
  ConsumerState<RenewalRequestScreen> createState() => _RenewalRequestScreenState();
}

class _RenewalRequestScreenState extends ConsumerState<RenewalRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _categories = [];
  
  String? _selectedEmployeeId; // Null means Company document renewal
  String? _selectedCategoryId;
  final _detailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchFormData();
  }

  Future<void> _fetchFormData() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profile = await supabase
          .from('users')
          .select('company_id')
          .eq('id', userId)
          .single();

      final companyId = profile['company_id'];

      if (companyId != null) {
        // Fetch employees
        final empRes = await supabase
            .from('employees')
            .select('id, first_name, last_name')
            .eq('company_id', companyId);
        
        _employees = List<Map<String, dynamic>>.from(empRes);

        // Fetch categories
        final catRes = await supabase
            .from('document_categories')
            .select('id, name');
        
        _categories = List<Map<String, dynamic>>.from(catRes);
      }
    } catch (e) {
      debugPrint("Error fetching renewal form options: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a document category')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final profile = await supabase
          .from('users')
          .select('company_id')
          .eq('id', userId)
          .single();

      final companyId = profile['company_id'];

      if (companyId != null) {
        // Spam prevention check
        var checkQuery = supabase
            .from('renewal_requests')
            .select('id')
            .eq('company_id', companyId)
            .eq('document_category_id', _selectedCategoryId!)
            .inFilter('status', ['pending', 'requested', 'in_progress']);

        if (_selectedEmployeeId != null) {
          checkQuery = checkQuery.eq('employee_id', _selectedEmployeeId!);
        } else {
          checkQuery = checkQuery.filter('employee_id', 'is', null);
        }

        final existing = await checkQuery;
        if (existing.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('A renewal request for this document is already active (requested or in progress).'),
                backgroundColor: Color(0xffef4444),
              ),
            );
          }
          return;
        }

        await supabase.from('renewal_requests').insert([
          {
            'company_id': companyId,
            'employee_id': _selectedEmployeeId, // Null if company level
            'document_category_id': _selectedCategoryId,
            'details': _detailsController.text.trim(),
            'status': 'requested',
          }
        ]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Renewal request submitted successfully!'),
              backgroundColor: Color(0xff316342),
            ),
          );
          context.pop(); // Go back to support screen
        }
      }
    } catch (e) {
      debugPrint("Error submitting renewal: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIndividual = ref.watch(isIndividualProvider);

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xff316342)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Renewal Request', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Document Category Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Document Category',
                    ),
                    items: _categories.map((cat) {
                      final name = (cat['name'] ?? '').toString();
                      final code = (cat['code'] ?? '').toString();
                      final isPartner = [
                        'partner',
                        'sponsor',
                        'shareholder',
                        'owner',
                        'passport',
                        'visa',
                        'eid',
                        'emirates id',
                        'insurance'
                      ].any((kw) => name.toLowerCase().contains(kw) || code.toLowerCase().contains(kw));
                      
                      final prefix = isPartner ? 'Partner' : 'Company';
                      return DropdownMenuItem<String>(
                        value: cat['id'],
                        child: Text('[$prefix] $name'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCategoryId = val;
                      });
                    },
                    validator: (val) => val == null ? 'Document category is required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Employee / Family Dropdown
                  DropdownButtonFormField<String?>(
                    value: _selectedEmployeeId,
                    decoration: InputDecoration(
                      labelText: isIndividual ? 'Family Member / Relative' : 'Sponsor Profile (Employee)',
                      helperText: isIndividual 
                          ? 'Leave empty for sponsor level renewals' 
                          : 'Leave empty for company licensing document renewals',
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(isIndividual 
                            ? 'Sponsor / Family Level Document' 
                            : 'Company Level Document (e.g. Trade License)'),
                      ),
                      ..._employees.map((emp) {
                        return DropdownMenuItem<String?>(
                          value: emp['id'],
                          child: Text("${emp['first_name']} ${emp['last_name']}"),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedEmployeeId = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Details Area
                  TextFormField(
                    controller: _detailsController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Request Details & Context',
                      hintText: 'Enter any additional instructions (e.g., expiry date, labor card ID, etc.)',
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Details are required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Action buttons
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Text('Submit Renewal Request'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
