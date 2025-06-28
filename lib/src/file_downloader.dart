import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:video_downloader/src/base_downloader.dart';
import 'package:video_downloader/src/download_status.dart';
import 'package:video_downloader/src/downloaderi.dart';
import 'package:video_downloader/src/media_utils.dart';

class FileDownloader extends BaseDownloader implements Downloaderi {
  FileDownloader({
    required super.outputFile,
    required super.videoUrl,
    required super.audioUrl,
    super.concurrentDownloads = 30,
    super.maxRetries = 10,
    super.progressUpdateStep = 1,
  });

  @override
  Future<void> startDownload({bool isResume = false}) async {
    if (!isResume) {
      await _cleanup();
      await videoDir.create(recursive: true);
      await audioDir.create(recursive: true);
    }
    cancelToken = CancelToken();

    statusController.add(DownloadStatus.DOWNLOADING);

    try {
      // Tính tổng dung lượng
      debugPrint(videoUrl);
      final videoSize = videoUrl != null ? await _getFileSize(videoUrl!) : 0;
      debugPrint(audioUrl);
      final audioSize = audioUrl != null ? await _getFileSize(audioUrl!) : 0;
      final totalSize = (videoSize ?? 0) + (audioSize ?? 0);

      int totalReceived = 0;
      File? audioFile;
      File? videoFile;
      // Tải video
      if (videoUrl != null) {
        final videoExt = await MediaUtils.getVideoExtentionFromUrl(videoUrl!);
        videoFile = File(p.join(videoDir.path, 'video.$videoExt'));
        await _downloadSegment(
          url: videoUrl!,
          segmentStart: 0,
          segmentEnd: videoSize! - 1,
          outputPath: videoFile.path,
          totalSize: totalSize,
          totalReceived: totalReceived,
          updateProgress: (bytesReceived) {
            totalReceived += bytesReceived;
            currentProgress = totalReceived / totalSize;
            updateProgress();
          },
        );
      }

      // Tải audio nếu có
      if (audioUrl != null) {
        final audioExt = await MediaUtils.getAudioExtentionFromUrl(audioUrl!);
        audioFile = File(p.join(audioDir.path, 'audio.$audioExt'));
        await _downloadSegment(
          url: audioUrl!,
          segmentStart: 0,
          segmentEnd: audioSize! - 1,
          outputPath: audioFile.path,
          totalSize: totalSize,
          totalReceived: totalReceived,
          updateProgress: (bytesReceived) {
            totalReceived += bytesReceived;
            currentProgress = totalReceived / totalSize;
            updateProgress();
          },
        );
      }

      // Ghép video và audio
      if (audioFile != null && videoFile != null) {
        await _mergeVideoAudio(videoFile.path, audioFile.path, outputFile);
      } else {
        if (audioFile != null) {
          audioFile.renameSync(outputFile);
        } else {
          videoFile!.renameSync(outputFile);
        }
      }

      statusController.add(DownloadStatus.DOWNLOADED);
      await _cleanup();
    } catch (e) {
      print('❌ Download failed: $e');
      statusController.add(DownloadStatus.FAILED);
    }
  }

  Future<void> _cleanup() async {
    if (await videoDir.exists()) await videoDir.delete(recursive: true);
    if (await audioDir.exists()) await audioDir.delete(recursive: true);
  }

  Future<void> _downloadSegment({
    required String url,
    required int segmentStart,
    required int segmentEnd,
    required String outputPath,
    required int totalSize,
    required int totalReceived,
    required void Function(int bytesReceived) updateProgress,
  }) async {
    final segmentDir = Directory(p.dirname(outputPath));
    await segmentDir.create(recursive: true);

    var segmentSize = 5 * 1024 * 1024; // 5 MB mỗi segment
    if (!await supportsByteRange(url)) {
      segmentSize = segmentEnd - segmentStart + 1;
    }
    final segmentCount = ((segmentEnd - segmentStart + 1) / segmentSize).ceil();
    List<File> segments = [];

    for (int i = 0; i < segmentCount; i++) {
      final start = segmentStart + i * segmentSize;
      final end = min(segmentStart + (i + 1) * segmentSize - 1, segmentEnd);
      final segmentFile = File('${outputPath}segment$i');
      final segmentTempFile = File('${outputPath}segment$i.tmp');
      if (segmentFile.existsSync()) {
        // Nếu segment đã tồn tại, bỏ qua
        segments.add(segmentFile);
        updateProgress(end - start + 1);
        continue;
      }
      segments.add(segmentFile);

      await _downloadInChunks(url: url, outputFile: segmentTempFile, start: start, end: end, totalSize: totalSize, totalReceived: totalReceived, updateProgress: updateProgress);
      segmentTempFile.renameSync(segmentFile.path);
    }

    // Ghép các segment lại với nhau
    await _mergeSegments(segments, File(outputPath));
  }

  Future<void> _mergeSegments(List<File> segments, File outputFile) async {
    final sink = outputFile.openWrite();
    for (final segment in segments) {
      sink.add(await segment.readAsBytes());
      await segment.delete(); // Xóa segment sau khi ghép
    }
    await sink.close();
  }

  Future<void> _downloadInChunks({
    required String url,
    required File outputFile,
    required int start,
    required int end,
    required int totalSize,
    required int totalReceived,
    required void Function(int bytesReceived) updateProgress,
  }) async {
    final chunkSize = ((end - start + 1) / concurrentDownloads).ceil();
    List<Future<File>> futures = [];
    List<File> parts = [];

    for (int i = 0; i < concurrentDownloads; i++) {
      final chunkStart = start + i * chunkSize;
      final chunkEnd = min(chunkStart + chunkSize - 1, end);

      if (chunkStart > chunkEnd) break;

      final partFile = File('${outputFile.path}.part$i');
      parts.add(partFile);

      int chunkReceived = 0;

      futures.add(
        _downloadChunkWithRetry(
          url: url,
          outputPath: partFile.path,
          start: chunkStart,
          end: chunkEnd,
          updateProgress: (bytesReceived) {
            final newBytes = bytesReceived - chunkReceived;
            chunkReceived = bytesReceived;
            updateProgress(newBytes);
          },
          retryLimit: maxRetries,
        ),
      );
    }

    final completedParts = await Future.wait(futures);

    final sink = outputFile.openWrite();
    for (final part in completedParts) {
      sink.add(await part.readAsBytes());
      await part.delete();
    }
    await sink.close();
  }

  Future<File> _downloadChunkWithRetry({
    required String url,
    required String outputPath,
    required int start,
    required int end,
    required void Function(int bytesReceived) updateProgress,
    int retryLimit = 3,
  }) async {
    for (int attempt = 0; attempt < retryLimit; attempt++) {
      try {
        await dio.download(
          url,
          outputPath,
          options: Options(headers: {'Range': 'bytes=$start-$end'}),
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            updateProgress(received);
          },
        );
        return File(outputPath);
      } catch (e) {
        print('⚠️ Failed to download chunk ($start-$end), attempt $attempt: $e');
        if (attempt == retryLimit - 1) {
          throw Exception('Failed to download chunk after $retryLimit attempts: $e');
        }
        Future.delayed(Duration(seconds: 3));
      }
    }
    throw Exception('Unexpected error in _downloadChunkWithRetry');
  }

  Future<bool> supportsByteRange(String url) async {
    try {
      Response response = await Dio().head(url, options: Options(headers: {'Range': 'bytes=0-1'}));
      return response.statusCode == 206 || response.headers.value('accept-ranges') == 'bytes';
    } catch (e) {
      return false;
    }
  }

  Future<int?> _getFileSize(String url) async {
    // Thử lấy kích thước qua Content-Length
    final sizeFromHead = await _getFileSizeWithContentLength(url);
    if (sizeFromHead != null) {
      print('File size retrieved from Content-Length: $sizeFromHead bytes');
      return sizeFromHead;
    }

    // Nếu Content-Length không khả dụng, thử FFprobe
    final sizeFromFFprobe = await _getFileSizeWithFFprobe(url);
    if (sizeFromFFprobe != null) {
      print('File size retrieved from FFprobe: $sizeFromFFprobe bytes');
      return sizeFromFFprobe;
    }

    // Nếu cả hai phương pháp đều thất bại
    print('Unable to fetch file size for URL: $url');
    return null;
  }

  Future<int?> _getFileSizeWithContentLength(String url) async {
    try {
      final res = await dio.head(url);
      final contentLength = res.headers[HttpHeaders.contentLengthHeader];
      if (contentLength != null) {
        return int.parse(contentLength.first);
      }
      print('Content-Length header is missing.');
      return null;
    } catch (e) {
      print('Error fetching file size with Content-Length: $e');
      return null;
    }
  }

  Future<int?> _getFileSizeWithFFprobe(String url) async {
    try {
      final info = await FFprobeKit.getMediaInformation(url);
      final size = info.getMediaInformation()!.getSize();
      if (size != null) {
        return int.parse(size);
      }
      print('FFprobe could not retrieve file size.');
      return null;
    } catch (e) {
      print('Error fetching file size with FFprobe: $e');
      return null;
    }
  }

  Future<void> _mergeVideoAudio(String videoPath, String audioPath, String outputPath) async {
    final cmd = '-i "$videoPath" -i "$audioPath" -c copy -y "$outputPath"';
    debugPrint(cmd);
    final session = await FFmpegKit.execute(cmd);
    final code = await session.getReturnCode();
    if (!code!.isValueSuccess()) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg failed: $logs');
    }
  }

  void updateProgress() {
    if ((currentProgress - lastReportedProgress) >= (progressUpdateStep / 100)) {
      lastReportedProgress = currentProgress;
      progressController.add(currentProgress);
    }
  }

  void dispose() {
    progressController.close();
    statusController.close();
  }

  @override
  void pauseDownload() {
    cancelToken.cancel();
    isPaused = true;
    statusController.add(DownloadStatus.PAUSED);
  }

  @override
  void resumeDownload() {
    startDownload(isResume: true);
  }

  @override
  void stopDownload() {
    _cleanup();
    cancelToken.cancel('User cancelled download');
  }

  Future<bool> supportsHttpRange(String url) async {
    try {
      Dio dio = Dio();
      final response = await dio.head(url, options: Options(headers: {'Range': 'bytes=0-1'}));

      // Kiểm tra phản hồi
      if (response.statusCode == 206) {
        print('Server hỗ trợ HTTP Range.');
        return true;
      } else {
        print('Server không hỗ trợ HTTP Range.');
        return false;
      }
    } catch (e) {
      print('Lỗi khi kiểm tra HTTP Range: $e');
      return false;
    }
  }
}
