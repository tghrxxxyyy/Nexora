import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Manages a shell process lifecycle — start, I/O, resize, kill.
class TerminalSession {
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _killed = false;

  /// Fires raw bytes from the shell's stdout/stderr.
  final StreamController<List<int>> _outputCtrl =
      StreamController<List<int>>.broadcast();
  Stream<List<int>> get output => _outputCtrl.stream;

  /// Whether the underlying process is still alive.
  bool get isAlive => _process != null && !_killed;

  /// The working directory the shell was started in.
  final String workingDirectory;

  TerminalSession({required this.workingDirectory});

  /// Start the platform-default shell in [workingDirectory].
  Future<void> start() async {
    if (_process != null) return;

    try {
      final args = _shellArgs(workingDirectory);
      _process = await Process.start(
        args.executable,
        args.arguments,
        workingDirectory: workingDirectory,
        environment: _buildEnv(),
        // Ensure terminal-like behavior
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      _stdoutSub = _process!.stdout.listen(
        (data) {
          if (!_killed) _outputCtrl.add(data);
        },
        onError: (e) => _outputCtrl.addError(e),
        onDone: _onProcessDone,
        cancelOnError: false,
      );

      _stderrSub = _process!.stderr.listen(
        (data) {
          if (!_killed) _outputCtrl.add(data);
        },
        onError: (e) => _outputCtrl.addError(e),
        onDone: _onProcessDone,
        cancelOnError: false,
      );

      _process!.exitCode.then((_) {
        _onProcessDone();
      });
    } catch (e) {
      _outputCtrl.addError(e);
      rethrow;
    }
  }

  /// Write [data] (raw bytes) to the shell's stdin.
  void writeInput(List<int> data) {
    if (_process != null && !_killed) {
      _process!.stdin.add(data);
      unawaited(_process!.stdin.flush());
    }
  }

  /// Write a UTF-8 string directly to stdin (for paste etc.).
  void writeString(String text) {
    writeInput(utf8.encode(text));
  }

  /// Tell the shell process the terminal dimensions changed.
  void resize(int cols, int rows) {}

  /// Gracefully kill the shell process.
  Future<void> kill() async {
    _killed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;
    await _outputCtrl.close();
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  void _onProcessDone() {
    if (_killed) return;
    _killed = true;
    _process = null;
    _outputCtrl.close();
  }

  _ShellArgs _shellArgs(String cwd) {
    if (Platform.isMacOS) {
      // On macOS we use bash/zsh — get the login shell
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      return _ShellArgs(executable: shell, arguments: ['-il']);
    } else if (Platform.isWindows) {
      return _ShellArgs(executable: 'cmd.exe', arguments: ['/K']);
    } else {
      // Linux
      final shell = Platform.environment['SHELL'] ?? '/bin/bash';
      return _ShellArgs(executable: shell, arguments: ['--login', '-i']);
    }
  }

  Map<String, String> _buildEnv() {
    final env = Map<String, String>.from(Platform.environment);
    // Ensure TERM is set so programs know they're in a terminal
    env['TERM'] = 'xterm-256color';
    // Set a simpler prompt so it's not too noisy in the embedded terminal
    env['PS1'] = r'\w \$ ';
    return env;
  }

  void _clearBuffers() {
    // Clear any buffered data
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
  }
}

class _ShellArgs {
  final String executable;
  final List<String> arguments;

  const _ShellArgs({required this.executable, required this.arguments});
}
