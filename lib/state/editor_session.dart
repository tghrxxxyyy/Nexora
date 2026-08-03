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
    scrollController.verticalScroller.addListener(_onEditorScroll);
    _headings = document.isMarkdown
        ? _outlineService.extract(document.content)
        : const [];
    editorController.addListener(_onEditorChanged);
  }

  DocumentModel _document;
  final MarkdownOutlineService _outlineService;
  final CodeLineEditingController editorController;
  final CodeScrollController scrollController = CodeScrollController();
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
  double _previewScrollOffset = 0;
  double _editorScrollOffset = 0;
  double _splitRatio = 0.52;

  DocumentModel get document => _document;
  List<MarkdownHeading> get headings => _headings;
  bool get externallyChanged => _externallyChanged;
  bool get deletedOnDisk => _deletedOnDisk;
  bool get wordWrap => _wordWrap;
  MarkdownViewMode get viewMode => _viewMode;
  String? get previewAnchor => _previewAnchor;
  int get previewJumpId => _previewJumpId;
  double get previewScrollOffset => _previewScrollOffset;
  double get editorScrollOffset => _editorScrollOffset;
  double get splitRatio => _splitRatio;

  /// Purely bookkeeping — deliberately does NOT notify: scroll offset doesn't
  /// drive any rebuild (pane rebuilds are driven by the controller), and every
  /// session notification cascades into a full app rebuild via
  /// `AppController._createSession`.
  void setPreviewScrollOffset(double value) {
    if (_previewScrollOffset == value) return;
    _previewScrollOffset = value;
  }

  /// Purely bookkeeping — deliberately does NOT notify (same rationale as
  /// [setPreviewScrollOffset]): the split pane's local state drives the
  /// rebuild, and the value here only survives so each document remembers its
  /// own split ratio across mode switches.
  void setSplitRatio(double value) {
    _splitRatio = value.clamp(0.25, 0.75).toDouble();
  }

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

  /// Pushes external content into this session without losing the user's
  /// cursor position. Used to synchronize edits from a sibling pane that's
  /// showing the same document — the receiving pane keeps its own scroll
  /// and (when possible) caret line.
  void setExternalContent(String content) {
    if (content == _document.content) return;
    _suppressEditorChange = true;
    final previousSelection = editorController.selection;
    _document = _document.copyWith(content: content);
    editorController.text = content;
    // Restoring selection: clamp line indices against the new codeLines
    // length so we don't paint a caret on a deleted line.
    final lineCount = editorController.codeLines.length;
    if (lineCount > 0) {
      final baseIndex = previousSelection.baseIndex.clamp(0, lineCount - 1);
      final extentIndex = previousSelection.extentIndex.clamp(0, lineCount - 1);
      final baseLineLength = editorController.codeLines[baseIndex].text.length;
      final extentLineLength =
          editorController.codeLines[extentIndex].text.length;
      editorController.selection = CodeLineSelection(
        baseIndex: baseIndex,
        baseOffset: previousSelection.baseOffset.clamp(0, baseLineLength),
        extentIndex: extentIndex,
        extentOffset: previousSelection.extentOffset.clamp(0, extentLineLength),
        baseAffinity: previousSelection.baseAffinity,
        extentAffinity: previousSelection.extentAffinity,
      );
    }
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

  void _onEditorScroll() {
    final scroller = scrollController.verticalScroller;
    if (!scroller.hasClients) return;
    _editorScrollOffset = scroller.offset;
  }

  @override
  void dispose() {
    editorController.removeListener(_onEditorChanged);
    scrollController.verticalScroller.removeListener(_onEditorScroll);
    scrollController.verticalScroller.dispose();
    scrollController.dispose();
    findController.dispose();
    previewFindController.dispose();
    editorController.dispose();
    super.dispose();
  }
}
