import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../models/search_models.dart';
import '../state/app_controller.dart';
import 'ui_primitives.dart';

class GlobalSearchPanel extends StatefulWidget {
  const GlobalSearchPanel({required this.controller, super.key});

  final AppController controller;

  @override
  State<GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _GlobalSearchPanelState extends State<GlobalSearchPanel> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  Timer? _debounce;
  bool _caseSensitive = false;
  bool _regex = false;
  bool _wholeWord = false;
  bool _replaceVisible = false;

  SearchOptions get _options => SearchOptions(
    caseSensitive: _caseSensitive,
    useRegularExpression: _regex,
    wholeWord: _wholeWord,
    maxResults: 5000,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _queryFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _replaceController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final workspace = controller.activeWorkspace;
    final report = controller.searchReport;
    final replaceVisible = _replaceVisible || controller.globalReplaceRequested;
    return PanelSurface(
      child: Column(
        children: [
          PanelLabel(
            label: '全局搜索',
            trailing: replaceVisible
                ? AppIconButton(
                    icon: Icons.find_replace_rounded,
                    tooltip: '收起替换',
                    selected: true,
                    size: 27,
                    iconSize: 14,
                    onPressed: () {
                      controller.clearGlobalReplaceRequest();
                      setState(() => _replaceVisible = false);
                    },
                  )
                : AppIconButton(
                    icon: Icons.find_replace_rounded,
                    tooltip: '展开替换',
                    size: 27,
                    iconSize: 14,
                    onPressed: () => setState(() => _replaceVisible = true),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 0, 9, 9),
            child: Column(
              children: [
                SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _queryController,
                    focusNode: _queryFocus,
                    onChanged: (_) => _scheduleSearch(),
                    onSubmitted: (_) => _runSearch(),
                    style: const TextStyle(fontSize: 11.5),
                    decoration: InputDecoration(
                      hintText: '在工作区中搜索',
                      prefixIcon: const Icon(Icons.search_rounded, size: 15),
                      suffixIcon: _queryController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _queryController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 13),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _SearchToggle(
                      label: 'Aa',
                      tooltip: '区分大小写',
                      selected: _caseSensitive,
                      onTap: () {
                        setState(() => _caseSensitive = !_caseSensitive);
                        _runSearch();
                      },
                    ),
                    const SizedBox(width: 4),
                    _SearchToggle(
                      label: '.*',
                      tooltip: '正则表达式',
                      selected: _regex,
                      onTap: () {
                        setState(() => _regex = !_regex);
                        _runSearch();
                      },
                    ),
                    const SizedBox(width: 4),
                    _SearchToggle(
                      label: 'ab',
                      tooltip: '全词匹配',
                      selected: _wholeWord,
                      underline: true,
                      onTap: () {
                        setState(() => _wholeWord = !_wholeWord);
                        _runSearch();
                      },
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: Icons.arrow_forward_rounded,
                      tooltip: '搜索',
                      size: 27,
                      iconSize: 15,
                      selected: true,
                      onPressed: controller.searching ? null : _runSearch,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: AppMotion.standard,
                  curve: AppMotion.curve,
                  alignment: Alignment.topCenter,
                  child: replaceVisible
                      ? Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: _replaceController,
                                    style: const TextStyle(fontSize: 11.5),
                                    decoration: const InputDecoration(
                                      hintText: '替换为',
                                      prefixIcon: Icon(
                                        Icons.find_replace_rounded,
                                        size: 15,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              AppIconButton(
                                icon: Icons.done_all_rounded,
                                tooltip: '全部替换',
                                size: 31,
                                iconSize: 15,
                                accent: AppColors.coral,
                                onPressed:
                                    controller.searching ||
                                        report == null ||
                                        report.results.isEmpty
                                    ? null
                                    : _confirmReplace,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SignalDivider(),
          if (controller.searching)
            LinearProgressIndicator(
              minHeight: 1,
              color: AppColors.signal,
              backgroundColor: AppColors.surface,
            ),
          if (controller.searchError != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                controller.searchError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.coral, fontSize: 10.5),
              ),
            ),
          if (report != null && controller.searchError == null)
            _SearchSummary(report: report),
          Expanded(
            child: report == null || report.results.isEmpty
                ? _SearchEmpty(hasQuery: _queryController.text.isNotEmpty)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 14),
                    itemCount: report.results.length,
                    itemExtent: 57,
                    itemBuilder: (context, index) => _SearchResultRow(
                      result: report.results[index],
                      rootPath: workspace?.path,
                      onTap: () =>
                          controller.openSearchResult(report.results[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _scheduleSearch() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 360), _runSearch);
  }

  void _runSearch() {
    _debounce?.cancel();
    final query = _queryController.text;
    if (query.isEmpty) return;
    widget.controller.search(query, _options);
  }

  Future<void> _confirmReplace() async {
    final count = widget.controller.searchReport?.results.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('替换整个工作区'),
        content: Text('确认替换当前 $count 处匹配？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('全部替换'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.replaceAll(
        _queryController.text,
        _replaceController.text,
        _options,
      );
    }
  }
}

class _SearchToggle extends StatelessWidget {
  const _SearchToggle({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.underline = false,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: AnimatedContainer(
          width: 29,
          height: 25,
          duration: AppMotion.quick,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.signal.withValues(alpha: 0.11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.signal : AppColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'MapleMonoCN',
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: selected ? AppColors.signal : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({required this.report});

  final SearchReport report;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(
        children: [
          Text(
            '${report.results.length} 处',
            style: TextStyle(
              color: AppColors.signal,
              fontSize: 10.5,
              fontFamily: 'MapleMonoCN',
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '${report.matchedFileCount} 个文件',
            style: TextStyle(color: AppColors.textDim, fontSize: 10.5),
          ),
          const Spacer(),
          if (report.truncated)
            Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.amber),
        ],
      ),
    );
  }
}

class _SearchResultRow extends StatefulWidget {
  const _SearchResultRow({
    required this.result,
    required this.rootPath,
    required this.onTap,
  });

  final SearchResult result;
  final String? rootPath;
  final VoidCallback onTap;

  @override
  State<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<_SearchResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final root = widget.rootPath;
    final relative = root != null && p.isWithin(root, result.filePath)
        ? p.relative(result.filePath, from: root)
        : p.basename(result.filePath);
    final line = result.lineText.trim();
    final matchStart = line.toLowerCase().indexOf(
      result.matchedText.toLowerCase(),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          padding: const EdgeInsets.fromLTRB(11, 7, 9, 6),
          color: _hovered
              ? AppColors.signal.withValues(alpha: 0.032)
              : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 12,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      relative,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  Text(
                    '${result.lineNumber}:${result.columnNumber}',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9.5,
                      fontFamily: 'MapleMonoCN',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              _HighlightedExcerpt(
                text: line,
                matchStart: matchStart,
                matchLength: result.matchedText.length,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedExcerpt extends StatelessWidget {
  const _HighlightedExcerpt({
    required this.text,
    required this.matchStart,
    required this.matchLength,
  });

  final String text;
  final int matchStart;
  final int matchLength;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 10.5,
      fontFamily: 'MapleMonoCN',
    );
    if (matchStart < 0 || matchLength == 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    final end = (matchStart + matchLength).clamp(0, text.length);
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: text.substring(0, matchStart)),
          TextSpan(
            text: text.substring(matchStart, end),
            style: TextStyle(
              color: AppColors.background,
              backgroundColor: AppColors.acid,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        hasQuery ? Icons.search_off_rounded : Icons.manage_search_rounded,
        color: AppColors.textDim,
        size: 26,
      ),
    );
  }
}
