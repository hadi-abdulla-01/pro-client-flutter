import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';

class FileUtils {
  static Future<String> getFileExtension(String fileName) async {
    return p.extension(fileName);
  }

  static String getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  static String extractExtensionFromPath(String path) {
    if (path.contains('.')) {
      final parts = path.split('.');
      if (parts.length > 1) {
        final ext = parts.last.toLowerCase();
        if (['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext)) {
          return '.$ext';
        }
      }
    }
    return '';
  }

  static String getExtensionFromMimeType(String mimeType) {
    if (mimeType.isEmpty) return '';
    
    final lowerMime = mimeType.toLowerCase();
    if (lowerMime.contains('application/pdf')) return '.pdf';
    if (lowerMime.contains('image/jpeg') || lowerMime.contains('image/jpg')) return '.jpg';
    if (lowerMime.contains('image/png')) return '.png';
    if (lowerMime.contains('image/gif')) return '.gif';
    if (lowerMime.contains('image/webp')) return '.webp';
    if (lowerMime.contains('application/msword')) return '.doc';
    if (lowerMime.contains('wordprocessingml')) return '.docx';
    if (lowerMime.contains('excel') || lowerMime.contains('spreadsheetml')) return '.xlsx';
    if (lowerMime.contains('powerpoint') || lowerMime.contains('presentationml')) return '.pptx';
    
    return '';
  }

  static Future<String> detectExtensionFromUrl(String url, String fileName) async {
    // First try to get from URL path
    final urlPath = url.split('?').first;
    final urlExt = extractExtensionFromPath(urlPath);
    if (urlExt.isNotEmpty) return urlExt;

    // Then try from filename
    final nameExt = extractExtensionFromPath(fileName);
    if (nameExt.isNotEmpty) return nameExt;

    // Try to get from content-type header by making a HEAD request
    try {
      final dio = Dio();
      final response = await dio.head(url);
      final contentType = response.headers.value('content-type') ?? '';
      final mimeExt = getExtensionFromMimeType(contentType);
      if (mimeExt.isNotEmpty) return mimeExt;
    } catch (e) {
      // If HEAD request fails, continue to fallback
    }

    // Fallback to common extensions based on filename hints
    final lowerName = fileName.toLowerCase();
    if (lowerName.contains('pdf')) return '.pdf';
    if (lowerName.contains('doc')) return '.docx';
    if (lowerName.contains('xls')) return '.xlsx';
    if (lowerName.contains('ppt')) return '.pptx';
    if (lowerName.contains('jpg') || lowerName.contains('jpeg')) return '.jpg';
    if (lowerName.contains('png')) return '.png';
    if (lowerName.contains('gif')) return '.gif';

    // Default to .bin if unknown
    return '.bin';
  }
}