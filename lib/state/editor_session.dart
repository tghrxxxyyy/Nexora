import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

import '../models/document_model.dart';
import '../models/markdown_heading.dart';
import '../services/markdown_outline_service.dart';
import 'preview_find_controller.dart';

enum MarkdownViewMode { edit, split, preview }

class EditorSession extends ChangeNotifier {
  EditorSession(
    DocumentModel document, {
    this._outlineService = const MarkdownOutlineService(),
  }) : _document = document,
       editorController = CodeLineEditingController.fromText(document.content) {
    findController = CodeFindController(editorController);
    previewFindController = PreviewFindController();
    _headings = document.isMarkdown
        ? _outlineService.extract(document.content)
        : const [];
    editorController.addListener(_onEditorChanged);
  }

  DocumentModel _document;
  final MarkdownOutlineService _outlineService;
  final CodeLineEditingController editorController;
  late final CodeFindController findController;
  late final PreviewFindController previewFindController;
  late List<MarkdownHeading> _headings;
  bool _suppressEditorChange = false;
  bool _externallyChanged = false;
  bool _deletedOnDisk = false;
  bool _wordWrap = false;
  MarkdownViewMode _viewMode = MarkdownViewMode.preview;
  String? _previewAnchor;
  int _previewJumpId = 0;

  DocumentModel get document => _document;
  List<MarkdownHeading> get headings => _headings;
  bool get externallyChanged => _externallyChanged;
  bool get deletedOnDisk => _deletedOnDisk;
  bool get wordWrap => _wordWrap;
  MarkdownViewMode get viewMode => _viewMode;
  String? get previewAnchor => _previewAnchor;
  int get previewJumpId => _previewJumpId;

  void setViewMode(MarkdownViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();
  }

  void toggleWordWrap() {
    _wordWrap = !_wordWrap;
    notifyListeners();
  }

  void requestPreviewJump(String anchor) {
    _previewAnchor = anchor;
    _previewJumpId++;
    notifyListeners();
  }

  void adoptSavedDocument(DocumentModel document) {
    _document = document;
    _externallyChanged = false;
    _deletedOnDisk = false;
    notifyListeners();
  }

  void reloadFromDisk(DocumentModel document) {
    _suppressEditorChange = true;
    _document = document;
    editorController.text = document.content;
    editorController.clearHistory();
    _headings = document.isMarkdown
        ? _outlineService.extract(document.content)
        : const [];
    _externallyChanged = false;
    _deletedOnDisk = false;
    _suppressEditorChange = false;
    notifyListeners();
  }

  void replaceContentFromPreview(String content) {
    if (content == _document.content) return;
    _suppressEditorChange = true;
    _document = _document.copyWith(content: content);
    editorController.text = content;
    _headings = _document.isMarkdown
        ? _outlineService.extract(content)
        : const [];
    _suppressEditorChange = false;
    notifyListeners();
  }

  void markExternalChange() {
    if (_externallyChanged) return;
    _externallyChanged = true;
    notifyListeners();
  }

  void markDeleted() {
    if (_deletedOnDisk) return;
    _deletedOnDisk = true;
    notifyListeners();
  }

  void jumpTo(int lineNumber, int columnNumber) {
    final lineIndex = (lineNumber - 1).clamp(0, editorController.lineCount - 1);
    final lineLength = editorController.codeLines[lineIndex].text.length;
    final offset = (columnNumber - 1).clamp(0, lineLength);
    final position = CodeLinePosition(index: lineIndex, offset: offset);
    editorController.selection = CodeLineSelection.fromPosition(
      position: position,
    );
    editorController.makePositionCenterIfInvisible(position);
  }

  void _onEditorChanged() {
    if (_suppressEditorChange) return;
    final content = editorController.text;
    if (content == _document.content) return;
    _document = _document.copyWith(content: content);
    _headings = _document.isMarkdown
        ? _outlineService.extract(content)
        : const [];
    notifyListeners();
  }

  @override
  void dispose() {
    editorController.removeListener(_onEditorChanged);
    findController.dispose();
    previewFindController.dispose();
    editorController.dispose();
    super.dispose();
  }
}
