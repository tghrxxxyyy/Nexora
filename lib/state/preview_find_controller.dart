import 'package:flutter/material.dart';

class PreviewFindController extends ChangeNotifier {
  PreviewFindController() {
    queryController.addListener(_handleQueryChanged);
  }

  final TextEditingController queryController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  bool _isOpen = false;
  bool _caseSensitive = false;
  int _matchCount = 0;
  int _activeIndex = -1;
  int _focusRequestId = 0;
  int _navigationRequestId = 0;

  bool get isOpen => _isOpen;
  bool get caseSensitive => _caseSensitive;
  String get query => queryController.text;
  int get matchCount => _matchCount;
  int get activeIndex => _activeIndex;
  int get focusRequestId => _focusRequestId;
  int get navigationRequestId => _navigationRequestId;

  void open() {
    _isOpen = true;
    _focusRequestId++;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _activeIndex = _matchCount == 0 ? -1 : 0;
    _navigationRequestId++;
    notifyListeners();
  }

  void nextMatch() {
    if (_matchCount == 0) return;
    _activeIndex = (_activeIndex + 1) % _matchCount;
    _navigationRequestId++;
    notifyListeners();
  }

  void previousMatch() {
    if (_matchCount == 0) return;
    _activeIndex = (_activeIndex - 1 + _matchCount) % _matchCount;
    _navigationRequestId++;
    notifyListeners();
  }

  void updateMatchCount(int count) {
    final normalizedCount = count < 0 ? 0 : count;
    final normalizedIndex = normalizedCount == 0
        ? -1
        : _activeIndex < 0
        ? 0
        : _activeIndex % normalizedCount;
    if (_matchCount == normalizedCount && _activeIndex == normalizedIndex) {
      return;
    }
    _matchCount = normalizedCount;
    _activeIndex = normalizedIndex;
    notifyListeners();
  }

  void _handleQueryChanged() {
    _activeIndex = query.isEmpty || _matchCount == 0 ? -1 : 0;
    _navigationRequestId++;
    notifyListeners();
  }

  @override
  void dispose() {
    queryController.removeListener(_handleQueryChanged);
    queryController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
