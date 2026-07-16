import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

class DocumentViewerScreen extends StatelessWidget {
  final String url;
  final String fileName;

  const DocumentViewerScreen({
    super.key,
    required this.url,
    required this.fileName,
  });

  bool _isPdf() {
    final nameLower = fileName.toLowerCase();
    final urlLower = url.toLowerCase().split('?').first;
    return nameLower.endsWith('.pdf') || urlLower.endsWith('.pdf');
  }

  bool _isImage() {
    final nameLower = fileName.toLowerCase();
    final urlLower = url.toLowerCase().split('?').first;
    final imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    return imageExts.any((ext) => nameLower.endsWith(ext) || urlLower.endsWith(ext));
  }

  @override
  Widget build(BuildContext context) {
    final bool isPdf = _isPdf();
    final bool isImage = _isImage();

    return Scaffold(
      backgroundColor: TerraTheme.cream50,
      appBar: AppBar(
        title: Text(
          fileName,
          style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        foregroundColor: TerraTheme.charcoal800,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: isPdf
          ? SfPdfViewer.network(url)
          : isImage
              ? InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      url,
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
