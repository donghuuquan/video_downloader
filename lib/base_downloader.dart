import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:video_downloader/download_status.dart';

class BaseDownloader {
  int concurrentDownloads = 30;
  int maxRetries = 10;
  double lastReportedProgress = 0.0;
  int progressUpdateStep = 1; // milliseconds

  final Dio dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10), sendTimeout: const Duration(seconds: 10)));

  CancelToken cancelToken = CancelToken();

  final progressController = StreamController<double>.broadcast();
  final statusController = StreamController<DownloadStatus>.broadcast();

  Stream<double> get progressStream => progressController.stream;
  Stream<DownloadStatus> get statusStream => statusController.stream;
  double currentProgress = 0.0;
  bool isPaused = false;
  final String outputFile;
  final String? videoUrl;
  final String? audioUrl;
  late Directory videoDir;
  late Directory audioDir;
  late Directory workingDir;

  BaseDownloader({required this.outputFile, required this.videoUrl, required this.audioUrl, this.concurrentDownloads = 30, this.maxRetries = 10, this.progressUpdateStep = 1}) {
    workingDir = File(outputFile).parent;
    videoDir = Directory('${workingDir.path}/video_segments');
    audioDir = Directory('${workingDir.path}/audio_segments');
  }
}
