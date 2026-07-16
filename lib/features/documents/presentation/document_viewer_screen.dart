import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import '../../../core/theme.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;

  const DocumentViewerScreen({
    super.key,
    required this.url,
    required this.fileName,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  bool _isLoading = true;
  String _extension = 'jpg';

  @override
  void initState() {
    super.initState();
    _detectFileType();
  }

  Future<void> _detectFileType() async {
    final String path = widget.url.split('?').first;
    final String name = widget.fileName;

    // 1. Try to get it from storage path extension
    if (path.contains('.')) {
      final ext = path.split('.').last.toLowerCase();
      if (['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        if (mounted) {
          setState(() {
            _extension = ext;
            _isLoading = false;
          });
        }
        return;
      }
    }

    // 2. Try to get it from the display name extension
    if (name.contains('.')) {
      final ext = name.split('.').last.toLowerCase();
      if (['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        if (mounted) {
          setState(() {
            _extension = ext;
            _isLoading = false;
          });
        }
        return;
      }
    }

    // 3. Try to fetch the first few bytes using a Range GET request
    try {
      final response = await Dio().get<ResponseBody>(
        widget.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Range': 'bytes=0-15',
          },
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
      
      // Read bytes from the stream
      final bytesList = await response.data!.stream.first;
      final bytes = List<int>.from(bytesList);
      
      String detectedExt = '';
      
      // Check magic bytes
      if (bytes.length >= 4) {
        // PDF: %PDF
        if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
          detectedExt = 'pdf';
        }
        // PNG
        else if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
          detectedExt = 'png';
        }
        // JPEG
        else if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
          detectedExt = 'jpg';
        }
        // GIF
        else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
          detectedExt = 'gif';
        }
      }

      // If magic bytes didn't match, check content-type
      if (detectedExt.isEmpty) {
        if (contentType.contains('pdf')) {
          detectedExt = 'pdf';
        } else if (contentType.contains('image/png')) {
          detectedExt = 'png';
        } else if (contentType.contains('image/jpeg') || contentType.contains('image/jpg')) {
          detectedExt = 'jpg';
        } else if (contentType.contains('image/gif')) {
          detectedExt = 'gif';
        } else if (contentType.contains('image/webp')) {
          detectedExt = 'webp';
        }
      }

      if (detectedExt.isNotEmpty) {
        if (mounted) {
          setState(() {
            _extension = detectedExt;
            _isLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Range GET request failed to determine file type: $e');
    }

    // Fallback: Default to pdf if name contains "pdf" or similar keyword, else jpg
    if (name.toLowerCase().contains('pdf')) {
      if (mounted) {
        setState(() {
          _extension = 'pdf';
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _extension = 'jpg';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPdf = _extension == 'pdf';
    final bool isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(_extension);

    return Scaffold(
      backgroundColor: TerraTheme.cream50,
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        foregroundColor: TerraTheme.charcoal800,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: TerraTheme.gold500))
          : isPdf
              ? SfPdfViewer.network(widget.url)
              : isImage
                  ? InteractiveViewer(
                      child: Center(
                        child: Image.network(
                          widget.url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                color: TerraTheme.gold500,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image_outlined, size: 60, color: TerraTheme.neutral500),
                                const SizedBox(height: 12),
                                Text('Could not load image',
                                    style: GoogleFonts.nunitoSans(color: TerraTheme.neutral500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 60, color: TerraTheme.neutral500),
                          const SizedBox(height: 12),
                          Text('Preview not available for this file type.',
                              style: GoogleFonts.nunitoSans(color: TerraTheme.neutral500)),
                          const SizedBox(height: 8),
                          Text('Please download to open it.',
                              style: GoogleFonts.nunitoSans(fontSize: 13, color: TerraTheme.neutral500)),
                        ],
                      ),
                    ),
    );
  }
}
