import 'dart:html' as html;
import 'dart:convert';

void saveFileWeb(String content, String fileName) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;
  html.document.body?.children.add(anchor);
  anchor.click();
  html.Url.revokeObjectUrl(url);
}

Future<String?> pickFileWeb() async {
  final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
  uploadInput.accept = '.json';
  uploadInput.click();

  await uploadInput.onChange.first;

  if (uploadInput.files?.isEmpty ?? true) return null;

  final html.File file = uploadInput.files!.first;
  final reader = html.FileReader();
  reader.readAsText(file);

  await reader.onLoadEnd.first;
  return reader.result as String?;
}
