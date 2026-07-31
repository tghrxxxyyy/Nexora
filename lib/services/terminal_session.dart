import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pty2/pty2.dart';
import 'package:xterm/xterm.dart';

/// Describes the lifecycle state of a terminal pseudo-terminal process.
enum TerminalSessionStatus { idle, starting, running, exited, failed }

/// Owns one terminal emulator and its platform pseudo-terminal process.
class TerminalSession extends ChangeNotifier {
  TerminalSession({required this.workingDirectory, required this.displayIndex})
    : id = 'terminal-${_nextSessionId++}',
      terminal = Terminal(
        maxLines: 10000,
        mouseHandler: const _TerminalMouseHandler(),
      ) {
    terminal.onOutput = _handleTerminalOutput;
    terminal.onResize = _handleTerminalResize;
  }

  /// Counter used to create stable identifiers within the current app run.
  static int _nextSessionId = 1;

  /// Stable identifier used by the terminal layout tree.
  final String id;

  /// Directory in which the login shell starts.
  final String workingDirectory;

  /// Human-readable sequence number shown in the pane header.
  final int displayIndex;

  /// Terminal emulator that parses escape sequences and accepts direct input.
  final Terminal terminal;

  /// Active pseudo-terminal process, when one has been started.
  PseudoTerminal? _pty;

  /// Subscription that streams decoded PTY output into [terminal].
  StreamSubscription<String>? _outputSubscription;

  /// Current lifecycle state exposed to the terminal pane header.
  TerminalSessionStatus _status = TerminalSessionStatus.idle;

  /// Exit code reported by the shell after it terminates.
  int? _exitCode;

  /// Prevents duplicate shutdown work.
  bool _closing = false;

  /// Prevents callbacks from notifying listeners after disposal.
  bool _disposed = false;

  /// Current pseudo-terminal lifecycle state.
  TerminalSessionStatus get status => _status;

  /// Exit code reported by the shell, or null while it is running.
  int? get exitCode => _exitCode;

  /// True while the PTY can accept user input.
  bool get isAlive => _status == TerminalSessionStatus.running && _pty != null;

  /// Shell name and pane sequence displayed in the pane header.
  String get title => '${p.basename(_shellLaunch().executable)} $displayIndex';

  /// Sends one accumulated wheel gesture to an application in the alternate
  /// screen buffer.
  ///
  /// Parameters:
  /// - [lines]: signed line count; negative scrolls up and positive scrolls down.
  /// - [position]: zero-based terminal cell under the pointer.
  void sendAlternateBufferScroll({
    required int lines,
    required CellOffset position,
  }) {
    if (lines == 0 || !terminal.isUsingAltBuffer) return;

    final scrollUp = lines < 0;
    final stepCount = lines.abs().clamp(1, terminal.viewHeight);
    if (!terminal.mouseMode.reportScroll) {
      // Full-screen apps without mouse reporting conventionally receive arrows.
      for (var index = 0; index < stepCount; index++) {
        terminal.keyInput(
          scrollUp ? TerminalKey.arrowUp : TerminalKey.arrowDown,
        );
      }
      return;
    }

    final report = _encodeWheelMouseReport(
      scrollUp: scrollUp,
      position: position,
    );
    if (report == null) return;

    // Mouse-reporting TUIs own their alternate-buffer scrolling.
    for (var index = 0; index < stepCount; index++) {
      _writeString(report);
    }
  }

  /// Starts the user's interactive login shell in [workingDirectory].
  Future<void> start() async {
    if (_disposed ||
        _status == TerminalSessionStatus.starting ||
        _status == TerminalSessionStatus.running ||
        _status == TerminalSessionStatus.exited) {
      return;
    }

    _setStatus(TerminalSessionStatus.starting);
    final launch = _shellLaunch();
    try {
      // Keep PTY line discipline enabled so line feeds return to column zero.
      // The PTY dimensions are updated again as soon as TerminalView lays out.
      final pty = PseudoTerminal.start(
        launch.executable,
        launch.arguments,
        workingDirectory: workingDirectory,
        environment: _buildEnvironment(),
      );
      if (_disposed || _closing) {
        pty.kill();
        return;
      }
      _pty = pty;
      pty.resize(
        terminal.viewWidth.clamp(2, 1000),
        terminal.viewHeight.clamp(1, 1000),
      );
      _setStatus(TerminalSessionStatus.running);
      _outputSubscription = pty.out.listen(
        terminal.write,
        onError: _handleOutputError,
        cancelOnError: false,
      );
      unawaited(_observeExit(pty));
    } catch (error) {
      _setStatus(TerminalSessionStatus.failed);
      terminal.write('\r\nUnable to start terminal: $error\r\n');
    }
  }

  /// Writes text directly to the running PTY using UTF-8 encoding.
  ///
  /// Parameters:
  /// - [text]: text produced by the terminal emulator.
  void _writeString(String text) {
    final pty = _pty;
    if (!isAlive || pty == null || text.isEmpty) return;
    pty.write(text);
  }

  /// Resizes the PTY to match the visible terminal character grid.
  ///
  /// Parameters:
  /// - [columns]: number of visible character columns.
  /// - [rows]: number of visible character rows.
  void _resize(int columns, int rows) {
    final pty = _pty;
    if (pty == null || !isAlive) return;
    pty.resize(columns.clamp(2, 1000), rows.clamp(1, 1000));
  }

  /// Terminates this terminal process and stops forwarding its output.
  Future<void> kill() async {
    if (_closing) return;
    _closing = true;
    final pty = _pty;
    _pty = null;
    if (pty != null) {
      try {
        pty.kill();
      } catch (_) {
        // The child may already have exited between the state check and kill.
      }
    }
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    if (_status != TerminalSessionStatus.failed) {
      _setStatus(TerminalSessionStatus.exited);
    }
  }

  /// Releases callbacks and terminates the child process during app shutdown.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closing = true;
    terminal.onOutput = null;
    terminal.onResize = null;
    final pty = _pty;
    _pty = null;
    try {
      pty?.kill();
    } catch (_) {
      // Dispose must remain synchronous even when the process already exited.
    }
    unawaited(_outputSubscription?.cancel() ?? Future<void>.value());
    _outputSubscription = null;
    super.dispose();
  }

  /// Forwards terminal-emulator input to the PTY.
  ///
  /// Parameters:
  /// - [data]: encoded control sequence or text emitted by xterm.
  void _handleTerminalOutput(String data) {
    _writeString(data);
  }

  /// Forwards terminal grid size changes to the PTY.
  ///
  /// Parameters:
  /// - [columns]: visible character columns.
  /// - [rows]: visible character rows.
  /// - [pixelWidth]: rendered width in pixels, currently unused by PTY.
  /// - [pixelHeight]: rendered height in pixels, currently unused by PTY.
  void _handleTerminalResize(
    int columns,
    int rows,
    int pixelWidth,
    int pixelHeight,
  ) {
    _resize(columns, rows);
  }

  /// Encodes a wheel action using the mouse protocol selected by the child app.
  ///
  /// Parameters:
  /// - [scrollUp]: whether the wheel action moves toward earlier content.
  /// - [position]: zero-based terminal cell under the pointer.
  String? _encodeWheelMouseReport({
    required bool scrollUp,
    required CellOffset position,
  }) {
    final maxColumn = terminal.viewWidth > 0 ? terminal.viewWidth - 1 : 0;
    final maxRow = terminal.viewHeight > 0 ? terminal.viewHeight - 1 : 0;
    final column = position.x.clamp(0, maxColumn).toInt() + 1;
    final row = position.y.clamp(0, maxRow).toInt() + 1;
    // Xterm mouse button codes are 64 for wheel-up and 65 for wheel-down.
    final buttonCode = scrollUp ? 64 : 65;

    switch (terminal.mouseReportMode) {
      case MouseReportMode.normal:
        if (column > 223 || row > 223) return null;
        return '\x1b[M'
            '${String.fromCharCode(32 + buttonCode)}'
            '${String.fromCharCode(32 + column)}'
            '${String.fromCharCode(32 + row)}';
      case MouseReportMode.utf:
        if (column > 2015 || row > 2015) return null;
        return '\x1b[M'
            '${String.fromCharCode(32 + buttonCode)}'
            '${String.fromCharCode(32 + column)}'
            '${String.fromCharCode(32 + row)}';
      case MouseReportMode.sgr:
        return '\x1b[<$buttonCode;$column;${row}M';
      case MouseReportMode.urxvt:
        return '\x1b[${32 + buttonCode};$column;${row}M';
    }
  }

  /// Reports a PTY output-stream error inside the terminal viewport.
  ///
  /// Parameters:
  /// - [error]: stream error returned by the native PTY implementation.
  void _handleOutputError(Object error) {
    terminal.write('\r\nTerminal output error: $error\r\n');
  }

  /// Tracks shell termination without discarding the PTY's buffered output.
  ///
  /// Parameters:
  /// - [pty]: PTY instance whose exit code is being observed.
  Future<void> _observeExit(PseudoTerminal pty) async {
    final code = await pty.exitCode;
    if (_disposed || !identical(_pty, pty)) return;
    _pty = null;
    _exitCode = code;
    _setStatus(TerminalSessionStatus.exited);
  }

  /// Updates [status] and notifies pane chrome when the lifecycle changes.
  ///
  /// Parameters:
  /// - [value]: new lifecycle state.
  void _setStatus(TerminalSessionStatus value) {
    if (_status == value) return;
    _status = value;
    if (!_disposed) notifyListeners();
  }

  /// Returns the executable and arguments for the user's login shell.
  _ShellLaunch _shellLaunch() {
    if (Platform.isWindows) {
      return _ShellLaunch(
        executable:
            Platform.environment['SHELL'] ??
            Platform.environment['COMSPEC'] ??
            'cmd.exe',
        arguments: const [],
      );
    }

    final executable = Platform.environment['SHELL'] ?? '/bin/bash';
    final shellName = p.basename(executable).toLowerCase();
    final arguments = shellName == 'fish'
        ? const ['--interactive', '--login']
        : const ['-il'];
    return _ShellLaunch(executable: executable, arguments: arguments);
  }

  /// Builds a true-color environment without replacing user prompt settings.
  Map<String, String> _buildEnvironment() {
    final environment = Map<String, String>.from(Platform.environment);
    // Interactive tools use these values to enable full terminal behavior.
    environment['TERM'] = 'xterm-256color';
    environment['COLORTERM'] = 'truecolor';
    environment['TERM_PROGRAM'] = 'Nexora';
    // Claude's fullscreen virtual scroller depends on xterm.js-specific input.
    // Native scrollback keeps wheel scrolling available in this Flutter terminal.
    environment.putIfAbsent('CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN', () => '1');
    return environment;
  }
}

/// Immutable shell launch command used when starting a PTY.
class _ShellLaunch {
  const _ShellLaunch({required this.executable, required this.arguments});

  /// Absolute path or command name of the user's shell.
  final String executable;

  /// Arguments that make the Unix shell interactive and login-aware.
  final List<String> arguments;
}

/// Preserves regular pointer reporting while the pane owns wheel dispatch.
class _TerminalMouseHandler implements TerminalMouseHandler {
  const _TerminalMouseHandler();

  /// Encodes non-wheel mouse events with xterm's default protocol handler.
  ///
  /// Parameters:
  /// - [event]: mouse input generated by the terminal viewport.
  @override
  String? call(TerminalMouseEvent event) {
    // The pane sends wheel input itself with corrected codes and local position.
    if (event.button.isWheel) return null;
    return defaultMouseHandler(event);
  }
}
