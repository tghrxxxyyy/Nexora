import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../app_theme.dart';
import '../state/app_controller.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.activeSession;
    return Container(
      height: 27,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.background,
            AppColors.backgroundRaised,
            AppColors.surface.withValues(alpha: 0.64),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        children: [
          const _LiveIndicator(),
          const SizedBox(width: 12),
          if (session != null)
            ValueListenableBuilder<CodeLineEditingValue>(
              valueListenable: session.editorController,
              builder: (context, value, child) {
                return Text(
                  '行 ${value.selection.extentIndex + 1}  列 ${value.selection.extentOffset + 1}',
                  style: _statusStyle,
                );
              },
            ),
          const SizedBox(width: 15),
          if (session != null)
            Text(
              '${session.document.lineCount} 行  ·  ${session.document.characterCount} 字符',
              style: _statusStyle,
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.standard,
              child: controller.message == null
                  ? const SizedBox.shrink()
                  : Text(
                      controller.message!,
                      key: ValueKey(controller.message),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _messageColor(controller.messageTone),
                        fontSize: 10.5,
                      ),
                    ),
            ),
          ),
          if (session != null) ...[
            if (session.document.isDirty)
              Padding(
                padding: EdgeInsets.only(right: 11),
                child: Text(
                  'EDITED',
                  style: TextStyle(
                    color: AppColors.acid,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'MapleMonoCN',
                  ),
                ),
              ),
            Text(
              p.extension(session.document.path).isEmpty
                  ? 'TEXT'
                  : p
                        .extension(session.document.path)
                        .substring(1)
                        .toUpperCase(),
              style: _statusStyle,
            ),
            const SizedBox(width: 14),
            Text('UTF-8', style: _statusStyle),
          ],
        ],
      ),
    );
  }

  Color _messageColor(AppMessageTone tone) {
    return switch (tone) {
      AppMessageTone.success => AppColors.acid,
      AppMessageTone.warning => AppColors.amber,
      AppMessageTone.error => AppColors.coral,
      AppMessageTone.neutral => AppColors.textMuted,
    };
  }
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.signal.withValues(
                alpha: 0.55 + _controller.value * 0.45,
              ),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: AppColors.signal,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'MapleMonoCN',
            ),
          ),
        ],
      ),
    );
  }
}

final _statusStyle = TextStyle(
  color: AppColors.textDim,
  fontSize: 9.5,
  fontFamily: 'MapleMonoCN',
);
