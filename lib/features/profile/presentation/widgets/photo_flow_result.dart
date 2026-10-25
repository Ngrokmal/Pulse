import 'dart:io';

class PhotoFlowResult {
  final File? file;
  final bool cancelled;

  const PhotoFlowResult.confirmed(File this.file) : cancelled = false;
  const PhotoFlowResult.cancelled()
      : file = null,
        cancelled = true;
}
