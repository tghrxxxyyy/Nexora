/// Payload carried by tab/sidebar drag operations targeting a split drop zone.
///
/// `sourcePaneId` is null when the drag originates from the file sidebar or a
/// tab strip (i.e. the source isn't already a pane in the split tree); set to
/// the originating pane's id when the user drags an existing pane to relocate
/// it. The drop zone uses it to ignore drops where source and target coincide.
class PaneDragPayload {
  const PaneDragPayload({required this.filePath, this.sourcePaneId});

  final String filePath;
  final String? sourcePaneId;

  @override
  String toString() =>
      'PaneDragPayload(filePath: $filePath, sourcePaneId: $sourcePaneId)';
}
