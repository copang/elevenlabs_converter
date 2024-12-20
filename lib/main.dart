import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'dart:html' as html;

enum DocType {
  stg,
  ntc,
  ntcShort
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

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
  String status = "";
  bool _isChecked = false;
  DocType? currentDocType;
  List<Chapter> chapters = [];
  List<Chapter> ntcContent = [];
  Part ntcShortContent = Part(lines: []);
  final breakTimeDefault = "<break time=“1.1s” />";
  final breakTimeSubtitle = "<break time=“0.5s” />";
  final breakTimeNumberic = "<break time=“0.3s” />";
  final specialPhrases = [
    "Quyển sách này nói về điều gì",
    "Về tác giả",
    "Quyển sách này dành cho ai"
  ];

  Future<void> _readNTCFile() async {
    currentDocType = DocType.ntc;
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
          ntcContent = [];
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
      int titleCount = 0;

      for (final paragraph in paragraphs) {
        StringBuffer paragraphBuffer = StringBuffer();
        for (final run in paragraph.findAllElements('w:r')) {
          final text = run.findElements('w:t').map((e) => e.text).join();
          paragraphBuffer.write(text);
        }

        // Nếu đoạn văn rỗng thì bỏ qua
        var paragraphText = paragraphBuffer.toString().trim();
        if (paragraphText.isEmpty) {
          continue;
        }

        titleCount++;
        currentChapter = Chapter(
          title: Line(content: titleCount.toString(), isBold: true),
          parts: [],
        );

        currentPart = Part(lines: []);
        if (_isChecked) {
          final sentences = _splitIntoSentences(paragraphText);
          for (var sentence in sentences) {
            currentPart.lines.add(Line(content: sentence, isBold: false));
          }
        } else {
          currentPart.lines.add(Line(content: paragraphText, isBold: false));
        }

        if (currentChapter.parts.isEmpty || currentChapter.parts.last != currentPart) {
          currentChapter.parts.add(currentPart);
        }

        tempChapters.add(currentChapter);
      }

      setState(() {
        ntcContent = tempChapters;
        status = 'Đã đọc xong file script Người Thành Công';
      });
    }
  }

  Future<void> _readNTCShortFile() async {
    currentDocType = DocType.ntcShort;
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
          ntcShortContent = Part(lines: []);
        });
        return;
      }

      // Đọc nội dung XML từ document.xml
      final contentXml = documentFile.content as List<int>;
      final documentXml = XmlDocument.parse(utf8.decode(contentXml));
      final paragraphs = documentXml.findAllElements('w:p');
      Part currentPart = Part(lines: []);

      for (final paragraph in paragraphs) {
        StringBuffer paragraphBuffer = StringBuffer();
        for (final run in paragraph.findAllElements('w:r')) {
          final text = run.findElements('w:t').map((e) => e.text).join();
          paragraphBuffer.write(text);
        }

        // Nếu đoạn văn rỗng thì bỏ qua
        var paragraphText = paragraphBuffer.toString().trim();
        if (paragraphText.isEmpty) {
          continue;
        }

        if (_isChecked) {
          final sentences = _splitIntoSentences(paragraphText);
          for (var sentence in sentences) {
            currentPart.lines.add(Line(content: sentence, isBold: false));
          }
        } else {
          currentPart.lines.add(Line(content: paragraphText, isBold: false));
        }
      }

      setState(() {
        ntcShortContent = currentPart;
        status = 'Đã đọc xong file script SHORT';
      });
    }
  }

  Future<void> _readSTGFile() async {
    currentDocType = DocType.stg;
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

        var paraText = paragraph.text;
        var paraXML = paragraph.toXmlString(pretty: true);

        for (final run in paragraph.findAllElements('w:r')) {
          final text = run.findElements('w:t').map((e) => e.text).join();

          // Kiểm tra phần tử `w:rPr` trong `w:r` để xác định in đậm
          // final isBold = run.findElements('w:rPr').any((rPr) {
          //   return rPr.findElements('w:b').isNotEmpty;
          // });

          final isBold = run.findElements('w:rPr').any((rPr) {
            return rPr.findElements('w:b').isNotEmpty || 
                  rPr.findElements('w:rStyle').any((rStyle) {
                    return rStyle.getAttribute('w:val') == 'Bold' || rStyle.getAttribute('w:val') == 'Strong';
                  });
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
              if (checkingPart.lines.length == 1 && checkingPart.lines.first.content.startsWith('-')) {
                //checkingPart.lines.last.content = breakTimeDefault;
                checkingPart.lines.add(Line(content: breakTimeDefault, isBold: false));
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
          currentPart ??= Part(lines: []);
          if (_isChecked) {
            final sentences = _splitIntoSentences(paragraphText);
            for (var sentence in sentences) {
              currentPart.lines.add(Line(content: sentence, isBold: false));
            }
          } else {
            currentPart.lines.add(Line(content: paragraphText, isBold: false));
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
        status = 'Đã đọc xong file script Sách Tinh Gọn';
      });
    }
  }

  // Điều chỉnh để không thêm break time cho Part cuối của mỗi Chapter
  void _addBreakTimeIfNecessary(Part part) {
    if (part.lines.isEmpty) return;
    if (part.lines.length == 1 && part.lines.first.content.startsWith('-')) {
      //part.lines.add(Line(content: breakTimeNumberic, isBold: false));
    } else {
      // Check for special phrases
      bool containsSpecialPhrase = part.lines.any((line) {
        return specialPhrases.any((phrase) => line.content.contains(phrase));
      });
      if (containsSpecialPhrase) {
        part.lines.add(Line(content: breakTimeSubtitle, isBold: false));
      } else {
        var firsLine = part.lines.first;
        if (!firsLine.content.startsWith('-')) {
          part.lines.add(Line(content: breakTimeDefault, isBold: false));
        }
      }
    }
  }

  List<String> _splitIntoSentences(String paragraph) {
    final sentenceRegEx = RegExp(
      // Loại trừ từ viết tắt
      r'(?<!\b(?:Mr|Ms|Mrs|Dr|St|U\.S\.A|U\.N|etc|vs))' 
      // Dấu câu theo sau bởi khoảng trắng và ký tự đầu là chữ in hoa
      //r'([.!?])\s+(?=[A-Z])'   
      r'([.!?])\s+(?=\p{Lu})'         
      // Không bao gồm dấu ngoặc kép/đơn sau dấu câu                 
      "(?![\"'])",
      unicode: true);                                   

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

  Future<void> _saveHtmlForSTG() async {
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
        ..setAttribute("download", "sach_tinh_gon_ai.html")
        ..click(); // Kích hoạt sự kiện tải xuống

      // Giải phóng URL sau khi tải xong
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<void> _saveHtmlForNTC() async {
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
    for (Chapter chapter in ntcContent) {
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
        fileName: 'ntc.html',
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
        ..setAttribute("download", "nguoi_thanh_cong_ai.html")
        ..click(); // Kích hoạt sự kiện tải xuống

      // Giải phóng URL sau khi tải xong
      html.Url.revokeObjectUrl(url);
    }
  }

  Future<void> _saveHtmlForNTCShort() async {
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

    for (Line line in ntcShortContent.lines) {
      String escapedContent = _escapeHtml(line.content);
      htmlContent.write("<p>$escapedContent</p>");
    }

    // Đóng body và html
    htmlContent.write("</body></html>");

    if (!kIsWeb) {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu file HTML',
        fileName: 'ntc_short.html',
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
        ..setAttribute("download", "nguoi_thanh_cong_short_ai.html")
        ..click(); // Kích hoạt sự kiện tải xuống

      // Giải phóng URL sau khi tải xong
      html.Url.revokeObjectUrl(url);
    }
  }

  // Hiển thị dữ liệu đã xử lý và nút "Copy"
  List<Widget> _buildWidgets() {
    if (currentDocType == DocType.ntc) {
      return ntcContent.map((chapter) {
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
              )
            ],
          )
        );
      }).toList();
    } else if (currentDocType == DocType.ntcShort) {
      var wg = Container(
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
                String shortContent = "";
                for (var line in ntcShortContent.lines) {
                  shortContent += "${line.content}\n";
                }

                Clipboard.setData(ClipboardData(text: shortContent));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã sao chép!")));
              },
              child: const Text("Sao chép"),
            ),
            const SizedBox(height: 10),
            RichText(
              text: TextSpan(
                children: [
                  ...ntcShortContent.lines.map((line) {
                    return TextSpan(
                      text: '${line.content}\n',
                      style: const TextStyle(
                        //fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                        color: Colors.black, // Cần chỉ định color cho TextSpan
                      ),
                    );
                  }),
                ],
              ),
            )
          ],
        )
      );
      return [wg];
    } else {
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
            Row(children: [
              Checkbox(
                value: _isChecked,
                onChanged: (bool? value) {
                  setState(() {
                    _isChecked = value ?? false;
                    currentDocType = null;
                    chapters = [];
                    ntcContent = [];
                    ntcShortContent = Part(lines: []);
                    status = 'Chưa mở file';
                  });
                },
              ),
              const Text('Tách câu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),)
            ],),
            const SizedBox(height: 20),
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
                  onPressed: _readNTCShortFile,
                  child: const Text("Chọn file Short NTC"),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: () {
                    if (currentDocType != null) {
                      switch (currentDocType) {
                        case DocType.stg:
                          _saveHtmlForSTG();
                          break;
                        case DocType.ntc:
                          _saveHtmlForNTC();
                          break;
                        case DocType.ntcShort:
                          _saveHtmlForNTCShort();
                          break;
                        default:
                      }
                    }
                  },
                  child: const Text("Xuất file HTML"),
                )
              ],
            ),
            const SizedBox(height: 100),
            currentDocType == null ? 
            const Text('Chưa mở file', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)) :
            Text(status, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
            // Expanded(
            //   child: SingleChildScrollView(
            //     child: Column(
            //       children: _buildWidgets(),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}