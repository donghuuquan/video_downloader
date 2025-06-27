abstract class Downloaderi {
  Future<void> startDownload({bool isResume = false});
  void stopDownload();
  void pauseDownload();
  void resumeDownload();
}
