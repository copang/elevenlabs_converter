import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'dart:html' as html;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: DocxReaderScreen(),
    );
  }
}

class Line {
  String content;
  final bool isBold;

  Line({required this.content, required this.isBold});
}

class Part {
  final List<Line> lines;

  Part({required this.lines});
}

class Chapter {
  final Line title;
  final List<Part> parts;

  Chapter({required this.title, required this.parts});
}

class DocxReaderScreen extends StatefulWidget {
  const DocxReaderScreen({super.key});

  @override
  State<DocxReaderScreen> createState() => _DocxReaderScreenState();
}

class _DocxReaderScreenState extends State<DocxReaderScreen> {
  List<Chapter> chapters = [];
  final breakTimeDefault = "<break time=“1.1s” />";
  final breakTimeSubtitle = "<break time=“0.5s” />";
  final breakTimeNumberic = "<break time=“0.3s” />";
  final specialPhrases = [
    "Quyển sách này nói về điều gì",
    "Về tác giả",
    "Quyển sách này dành cho ai"
  ];

  Future<void> _readNTCFile() async {
    
  }

  Future<void> _readSTGFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );

    if (result != null) {
      Archive? archive;

      // Giải nén file docx
      if (!kIsWeb) {
        File file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        archive = ZipDecoder().decodeBytes(bytes);
      } else {
        Uint8List? fileBytes = result.files.first.bytes;
        archive = ZipDecoder().decodeBytes(fileBytes as List<int>);
      }

      // Tìm file chứa văn bản (usually 'word/document.xml')
      ArchiveFile? documentFile;
      for (final file in archive.files) {
        if (file.name == 'word/document.xml') {
          documentFile = file;
          break;
        }
      }

      if (documentFile == null) {
        setState(() {
          chapters = [];
        });
        return;
      }

      // Đọc nội dung XML từ document.xml
      final contentXml = documentFile.content as List<int>;
      final documentXml = XmlDocument.parse(utf8.decode(contentXml));

      final paragraphs = documentXml.findAllElements('w:p');
      List<Chapter> tempChapters = [];
      Chapter? currentChapter;
      Part? currentPart;

      for (final paragraph in paragraphs) {
        StringBuffer paragraphBuffer = StringBuffer();
        bool isBoldParagraph = false;

        for (final run in paragraph.findAllElements('w:r')) {
          final text = run.findElements('w:t').map((e) => e.text).join();

          // Kiểm tra phần tử `w:rPr` trong `w:r` để xác định in đậm
          final isBold = run.findElements('w:rPr').any((rPr) {
            return rPr.findElements('w:b').isNotEmpty;
          });

          if (isBold) {
            isBoldParagraph = true;
          }

          paragraphBuffer.write(text);
        }

        // Nếu đoạn văn rỗng thì bỏ qua
        var paragraphText = paragraphBuffer.toString().trim();
        if (paragraphText.isEmpty) {
          continue;
        }

        // Kiểm tra xem đoạn này có phải là tiêu đề (in đậm) hay không
        bool containsSpecialPhrase = specialPhrases.any((phrase) => paragraphText.contains(phrase));
        if (isBoldParagraph && !containsSpecialPhrase) {
          // Tạo Chapter mới nếu gặp title mới
          if (currentChapter != null) {
            for (int i = currentChapter.parts.length - 1; i > 0; i--) {
              var checkingPart = currentChapter.parts[i];
              if (checkingPart.lines.length == 2 && checkingPart.lines.first.content.startsWith('-')) {
                checkingPart.lines.last.content = breakTimeDefault;
                break;
              }
            }   
            tempChapters.add(currentChapter);
          }
          currentChapter = Chapter(
            title: Line(content: paragraphText, isBold: true),
            parts: [],
          );
          currentPart = null; // Reset part cho Chapter mới
        } else {
          // Nếu không phải tiêu đề, tách đoạn văn thành câu
          final sentences = _splitIntoSentences(paragraphText);

          currentPart ??= Part(lines: []);

          for (var sentence in sentences) {
            currentPart.lines.add(Line(content: sentence, isBold: false));
          }

          // Mỗi khi hoàn thành một đoạn văn, sẽ thêm Part vào Chapter
          if (currentChapter != null) {
            if (currentChapter.parts.isEmpty || currentChapter.parts.last != currentPart) {
              _addBreakTimeIfNecessary(currentPart);
              currentChapter.parts.add(currentPart);
              currentPart = Part(lines: []); // Tạo Part mới cho đoạn văn tiếp theo
            }
          }
        }
      }

      // Add Chapter cuối cùng nếu có
      if (currentChapter != null) {
        _addBreakTimeIfNecessary(currentPart!);
        tempChapters.add(currentChapter);
      }

      // Xử lý yêu cầu chỉnh sửa break time
      for (var chapter in tempChapters) {
        if (chapter.parts.isNotEmpty) {
          var lastPart = chapter.parts.last;
          if (lastPart.lines.isNotEmpty && lastPart.lines.last.content.contains("break time")) {
            lastPart.lines.removeLast();
          }
        }
      }

      setState(() {
        chapters = tempChapters;
      });
    }
  }

  // Điều chỉnh để không thêm break time cho Part cuối của mỗi Chapter
  void _addBreakTimeIfNecessary(Part part) {
    if (part.lines.length == 1 && part.lines.first.content.startsWith('-')) {
      part.lines.add(Line(content: breakTimeNumberic, isBold: false));
    } else {
      // Check for special phrases
      bool containsSpecialPhrase = part.lines.any((line) {
        return specialPhrases.any((phrase) => line.content.contains(phrase));
      });
      if (containsSpecialPhrase) {
        part.lines.add(Line(content: breakTimeSubtitle, isBold: false));
      } else {
        part.lines.add(Line(content: breakTimeDefault, isBold: false));
      }
    }
  }

  List<String> _splitIntoSentences(String paragraph) {
    final sentenceRegEx = RegExp(r'([.!?])\s+');
    List<String> sentences = [];
    final matches = sentenceRegEx.allMatches(paragraph);

    int startIndex = 0;
    for (var match in matches) {
      String sentence = paragraph.substring(startIndex, match.end).trim();
      sentences.add(sentence);
      startIndex = match.end;
    }

    // Thêm câu cuối cùng nếu còn dư nội dung
    if (startIndex < paragraph.length) {
      sentences.add(paragraph.substring(startIndex).trim());
    }

    return sentences;
  }

  // Tính năng export HTML
  String _escapeHtml(String text) {
    return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  Future<void> _saveHtml() async {
    StringBuffer htmlContent = StringBuffer();

    // Thêm khai báo meta UTF-8
    htmlContent.write("""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Document</title>
    </head>
    <body>
    """);

    // Lặp qua từng Chapter và Part để tạo nội dung HTML
    for (Chapter chapter in chapters) {
      htmlContent.write("<h2>${_escapeHtml(chapter.title.content)}</h2>"); // Title là Heading 2
      for (Part part in chapter.parts) {
        for (Line line in part.lines) {
          String escapedContent = _escapeHtml(line.content);
          if (line.isBold) {
            // Nếu isBold = true thì xuất thẻ <b>
            htmlContent.write("<p><b>$escapedContent</b></p>");
          } else {
            // Xuất dòng bình thường với thẻ <p>
            htmlContent.write("<p>$escapedContent</p>");
          }
        }
      }
    }

    // Đóng body và html
    htmlContent.write("</body></html>");

    if (!kIsWeb) {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu file HTML',
        fileName: 'book.html',
        allowedExtensions: ['html'],
        type: FileType.custom,
      );
      if (result != null) {
        final file = File(result);
        await file.writeAsString(htmlContent.toString(), encoding: utf8);
      }
    } else {
      // Chuyển đổi nội dung HTML thành Uint8List
      final bytes = Uint8List.fromList(utf8.encode(htmlContent.toString()));

      // Tạo một Blob từ nội dung đã mã hóa
      final blob = html.Blob([bytes]);

      // Tạo URL để tải tệp
      final url = html.Url.createObjectUrlFromBlob(blob);

      // Tạo thẻ <a> để thực hiện tải file
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "doc_for_ai.html")
        ..click(); // Kích hoạt sự kiện tải xuống

      // Giải phóng URL sau khi tải xong
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<void> _saveHtmlOld() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu file HTML',
        fileName: 'book.html',
        allowedExtensions: ['html'],
        type: FileType.custom,
      );

      if (result != null) {
        final file = File(result);
        StringBuffer htmlContent = StringBuffer();

        // Thêm khai báo meta UTF-8
        htmlContent.write("""
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Document</title>
        </head>
        <body>
        """);

        // Lặp qua từng Chapter và Part để tạo nội dung HTML
        for (Chapter chapter in chapters) {
          htmlContent.write("<h2>${_escapeHtml(chapter.title.content)}</h2>"); // Title là Heading 2
          for (Part part in chapter.parts) {
            for (Line line in part.lines) {
              String escapedContent = _escapeHtml(line.content);
              if (line.isBold) {
                // Nếu isBold = true thì xuất thẻ <b>
                htmlContent.write("<p><b>$escapedContent</b></p>");
              } else {
                // Xuất dòng bình thường với thẻ <p>
                htmlContent.write("<p>$escapedContent</p>");
              }
            }
          }
        }

        // Đóng body và html
        htmlContent.write("</body></html>");

        // Lưu file với mã hóa UTF-8
        await file.writeAsString(htmlContent.toString(), encoding: utf8);
        print('Đã lưu file HTML tại ${file.path}');
      }
    } catch (e) {
      print('Lỗi khi lưu file HTML: $e');
    }
  }

  // Hiển thị dữ liệu đã xử lý và nút "Copy"
  List<Widget> _buildChapterWidgets() {
    return chapters.map((chapter) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.lightBlueAccent.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () {
                String chapterContent = "${chapter.title.content}\n";
                for (var part in chapter.parts) {
                  for (var line in part.lines) {
                    chapterContent += "${line.content}\n";
                  }
                }

                Clipboard.setData(ClipboardData(text: chapterContent));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã sao chép!")));
              },
              child: const Text("Sao chép"),
            ),
            const SizedBox(height: 10),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${chapter.title.content}\n',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black, // Cần chỉ định color cho TextSpan
                    ),
                  ),
                  ...chapter.parts.expand((part) {
                    return part.lines.map((line) {
                      return TextSpan(
                        text: '${line.content}\n',
                        style: const TextStyle(
                          //fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                          color: Colors.black, // Cần chỉ định color cho TextSpan
                        ),
                      );
                    });
                  }),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XỬ LÝ FILE DOCX CHO AI'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: _readSTGFile,
                  child: const Text("Chọn file SÁCH"),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _readNTCFile,
                  child: const Text("Chọn file NTC"),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _saveHtml,
                  child: const Text("Xuất file HTML"),
                )
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: _buildChapterWidgets(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}