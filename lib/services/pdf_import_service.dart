import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import 'ocr_service.dart';

class PdfImportResult {
  final String text;
  final int pageCount;
  final bool truncated;

  const PdfImportResult({
    required this.text,
    required this.pageCount,
    required this.truncated,
  });
}

class PdfChapter {
  final String title;
  final String content;

  const PdfChapter({required this.title, required this.content});
}

class PdfImportService {
  static final PdfImportService instance = PdfImportService._();
  PdfImportService._();

  static const _maxPagesChapter = 60;
  static const _maxPagesSubject = 150;

  /// Opens the system file picker and returns the chosen PDF path.
  Future<String?> pickPdfPath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    return result?.files.firstOrNull?.path;
  }

  /// Renders each PDF page as a JPEG and runs on-device OCR on it.
  Future<PdfImportResult> extractText(
    String pdfPath, {
    void Function(String status)? onStatus,
    int maxPages = _maxPagesChapter,
  }) async {
    onStatus?.call('Opening PDF…');
    final doc = await PdfDocument.openFile(pdfPath);
    final total = doc.pagesCount;
    final limit = total.clamp(1, maxPages);
    final truncated = total > maxPages;

    final buffer = StringBuffer();
    final tempDir = await getTemporaryDirectory();

    for (int i = 1; i <= limit; i++) {
      onStatus?.call('Scanning page $i of $total…');
      PdfPage? page;
      PdfPageImage? image;
      File? tmpFile;
      try {
        page = await doc.getPage(i);
        image = await page.render(
          width: (page.width * 2).toInt(),
          height: (page.height * 2).toInt(),
          format: PdfPageImageFormat.jpeg,
          quality: 88,
          backgroundColor: '#FFFFFF',
        );
        if (image?.bytes == null) continue;

        tmpFile = File(
          '${tempDir.path}/pdf_p${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tmpFile.writeAsBytes(image!.bytes!);

        final pageText = await OcrService.instance.recognizeFromFile(tmpFile.path);
        if (pageText.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n\n');
          buffer.write(pageText);
        }
      } catch (_) {
        // skip unreadable pages silently
      } finally {
        await image?.close();
        await page?.close();
        await tmpFile?.delete().catchError((_) {});
      }
    }

    await doc.close();

    return PdfImportResult(
      text: buffer.toString(),
      pageCount: total,
      truncated: truncated,
    );
  }

  /// Detects chapter/unit/section headings in OCR'd text using regex.
  /// Returns [] if no recognisable structure is found.
  List<PdfChapter> detectChapters(String text) {
    // Matches "Chapter 1", "Unit 2:", "PART III –", "Lesson 4." etc.
    final pattern = RegExp(
      r'(?:^|\n{2,})'
      r'((?:CHAPTER|Chapter|chapter|UNIT|Unit|unit|PART|Part|part|'
      r'SECTION|Section|section|LESSON|Lesson|lesson)\s+'
      r'(?:\d+(?:\.\d+)*|[IVXLCDMivxlcdm]+'
      r'|one|two|three|four|five|six|seven|eight|nine|ten'
      r'|ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN)'
      r'[.:)–\-]?\s*[^\n]*)',
      multiLine: true,
    );

    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return [];

    final chapters = <PdfChapter>[];
    for (int i = 0; i < matches.length; i++) {
      final title = matches[i].group(1)?.trim() ?? 'Chapter ${i + 1}';
      final contentStart = matches[i].end;
      final contentEnd =
          i < matches.length - 1 ? matches[i + 1].start : text.length;
      final content = text.substring(contentStart, contentEnd).trim();
      if (content.length > 40) {
        chapters.add(PdfChapter(title: title, content: content));
      }
    }
    return chapters;
  }
}
