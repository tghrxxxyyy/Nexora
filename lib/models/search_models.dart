class SearchOptions {
  const SearchOptions({
    this.caseSensitive = false,
    this.useRegularExpression = false,
    this.wholeWord = false,
    this.maxFileBytes = 8 * 1024 * 1024,
    this.maxResults = 10000,
    this.includedExtensions = const <String>{},
    this.excludedPaths = const <String>{},
  });

  final bool caseSensitive;
  final bool useRegularExpression;
  final bool wholeWord;
  final int maxFileBytes;
  final int maxResults;
  final Set<String> includedExtensions;
  final Set<String> excludedPaths;
}

class SearchResult {
  const SearchResult({
    required this.filePath,
    required this.lineNumber,
    required this.columnNumber,
    required this.lineText,
    required this.matchedText,
    required this.startOffset,
    required this.endOffset,
  });

  final String filePath;
  final int lineNumber;
  final int columnNumber;
  final String lineText;
  final String matchedText;
  final int startOffset;
  final int endOffset;
}

class SearchReport {
  const SearchReport({
    required this.results,
    required this.scannedFileCount,
    required this.skippedBinaryFileCount,
    required this.skippedLargeFileCount,
    required this.errors,
    required this.truncated,
  });

  final List<SearchResult> results;
  final int scannedFileCount;
  final int skippedBinaryFileCount;
  final int skippedLargeFileCount;
  final List<String> errors;
  final bool truncated;

  int get matchedFileCount =>
      results.map((result) => result.filePath).toSet().length;
}

class ReplaceReport {
  const ReplaceReport({
    required this.changedFileCount,
    required this.replacementCount,
    required this.scannedFileCount,
    required this.skippedBinaryFileCount,
    required this.skippedLargeFileCount,
    required this.errors,
  });

  final int changedFileCount;
  final int replacementCount;
  final int scannedFileCount;
  final int skippedBinaryFileCount;
  final int skippedLargeFileCount;
  final List<String> errors;
}
