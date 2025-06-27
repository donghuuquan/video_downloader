import 'package:flutter/material.dart';
import 'package:video_downloader/base_downloader.dart';
import 'package:video_downloader/download_status.dart';
import 'package:video_downloader/downloaderi.dart';
import 'package:video_downloader/file_downloader.dart';
import 'package:video_downloader/m3u8_downloader.dart';

class VideoDownloader extends BaseDownloader implements Downloaderi {
  VideoDownloader({
    required super.outputFile,
    required super.videoUrl,
    required super.audioUrl,
    super.concurrentDownloads = 30,
    super.maxRetries = 10,
    super.progressUpdateStep = 1,
  }) {
    var url = (videoUrl ?? '') + (audioUrl ?? '');
    if (url.contains('.m3u8')) {
      isM3U8 = true;
      m3u8downloader = M3U8Downloader(
        outputFile: super.outputFile,
        videoUrl: super.videoUrl,
        audioUrl: super.audioUrl,
        concurrentDownloads: super.concurrentDownloads,
        maxRetries: super.maxRetries,
        progressUpdateStep: super.progressUpdateStep,
      );

      m3u8downloader?.progressStream.listen((progress) {
        progressController.add(progress);
      });

      m3u8downloader?.statusStream.listen((status) {
        statusController.add(status);
      });
    } else {
      fileDownloader = FileDownloader(
        outputFile: super.outputFile,
        videoUrl: super.videoUrl,
        audioUrl: super.audioUrl,
        concurrentDownloads: super.concurrentDownloads,
        maxRetries: super.maxRetries,
        progressUpdateStep: super.progressUpdateStep,
      );
      fileDownloader?.progressStream.listen((progress) {
        progressController.add(progress);
      });

      fileDownloader?.statusStream.listen((status) {
        statusController.add(status);
      });
    }
  }
  M3U8Downloader? m3u8downloader;
  FileDownloader? fileDownloader;
  bool isM3U8 = false;
  @override
  Future<void> startDownload({bool isResume = false}) async {
    // Nếu không truyền audio và link video vào thì báo lỗi
    if (videoUrl == null && audioUrl == null) {
      statusController.add(DownloadStatus.FAILED);
      return;
    }
    if (isM3U8) {
      await m3u8downloader!.startDownload(isResume: isResume);
    } else {
      await fileDownloader!.startDownload(isResume: isResume);
    }
  }

  @override
  void pauseDownload() {
    if (isM3U8) {
      m3u8downloader!.pauseDownload();
    } else {
      fileDownloader!.pauseDownload();
    }
  }

  @override
  void resumeDownload() {
    if (isM3U8) {
      m3u8downloader!.resumeDownload();
    } else {
      fileDownloader!.resumeDownload();
    }
  }

  @override
  void stopDownload() {
    if (isM3U8) {
      m3u8downloader!.stopDownload();
    } else {
      fileDownloader!.stopDownload();
    }
  }
}
