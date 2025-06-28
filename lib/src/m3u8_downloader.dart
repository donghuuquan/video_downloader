import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hls_parser/flutter_hls_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_downloader/src/base_downloader.dart';
import 'package:video_downloader/src/download_status.dart';
import 'package:video_downloader/src/downloaderi.dart';
import 'package:path/path.dart' as p;

class M3U8Downloader extends BaseDownloader implements Downloaderi {
  CancelToken _cancelToken = CancelToken();

  // State variables from M3U8DownloaderState
  List<Map<String, dynamic>> videoJobs = [];
  List<Map<String, dynamic>> audioJobs = [];
  int videoDownloaded = 0;
  int audioDownloaded = 0;
  int videoTotal = 0;
  int audioTotal = 0;

  M3U8Downloader({
    required super.outputFile,
    required super.videoUrl,
    required super.audioUrl,
    super.concurrentDownloads = 30,
    super.maxRetries = 10,
    super.progressUpdateStep = 1,
  });

  @override
  Future<void> startDownload({bool isResume = false}) async {
    statusController.add(DownloadStatus.DOWNLOADING);

    _cancelToken = CancelToken();
    reset();

    try {
      if (!isResume) {
        await _cleanup();
        await videoDir.create(recursive: true);
        await audioDir.create(recursive: true);
      }

      if (videoUrl != null) {
        videoJobs = await _parseM3U8(videoUrl!, videoDir.path);
        debugPrint('Video url: $videoUrl');
        debugPrint('Video jobs: ${videoJobs.length}');
        videoTotal = videoJobs.where((job) => job.containsKey('segment')).length;
        videoDownloaded = 0;
      }

      if (audioUrl != null && audioUrl!.isNotEmpty) {
        audioJobs = await _parseM3U8(audioUrl!, audioDir.path);

        debugPrint('Audio url: $audioUrl');
        debugPrint('Video jobs: ${audioJobs.length}');
        audioTotal = audioJobs.where((job) => job.containsKey('segment')).length;
        audioDownloaded = 0;
      }

      final totalSegments = videoTotal + audioTotal;
      if (totalSegments == 0) {
        statusController.add(DownloadStatus.DOWNLOADED);
        return;
      }

      // Download video
      await Future.wait([if (videoJobs.isNotEmpty) _downloadInBatches(videoJobs, batchSize: concurrentDownloads, isVideo: true)]);
      // Download audio
      await Future.wait([if (audioJobs.isNotEmpty) _downloadInBatches(audioJobs, batchSize: concurrentDownloads, isVideo: false)]);

      if (!isPaused && !_cancelToken.isCancelled) {
        await _mergeVideoAudio(p.basename(File(outputFile).path), videoUrl, audioUrl);
      }
    } catch (e) {
      if (isPaused) {
        statusController.add(DownloadStatus.PAUSED);
      } else {
        statusController.add(DownloadStatus.FAILED);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _parseM3U8(String m3u8Url, String saveDir) async {
    debugPrint(m3u8Url);
    final response = await dio.get(m3u8Url);

    final playList = await HlsPlaylistParser.create().parseString(Uri.parse(m3u8Url), response.data.toString());
    playList as HlsMediaPlaylist;

    List<Map<String, dynamic>> jobs = [];
    final baseUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf("/") + 1);
    int i = 0;
    for (var segment in playList.segments) {
      //final segUrl = segment.url!.startsWith('http') ? segment.url! : baseUrl + segment.url!;
      final cleanUrl = segment.url!.split('?').first;
      final ext = p.extension(cleanUrl);
      final path = '$saveDir/seg_${i.toString().padLeft(4, '0')}.ts';

      jobs.add({'index': i.toString(), 'segment': segment, 'base_url': baseUrl, 'path': path, 'retries': '0'});
      i++;
    }
    for (int i = 0; i < playList.segments.length; i++) {}

    return jobs;

    //-----------------------------Xử lý thủ công----------------------------//
    /*
    final response = await dio.get(m3u8Url);
    final lines = response.data.toString().split('\n');

    if (!lines.any((line) => line.startsWith('#EXTM3U'))) {
      throw Exception('File không phải là playlist M3U8 hợp lệ: $m3u8Url');
    }

    final isMasterPlaylist = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));
    if (isMasterPlaylist) {
      final variantStreams = <Map<String, String>>[];
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
          final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
          final bandwidth = bandwidthMatch != null ? int.parse(bandwidthMatch.group(1)!) : 0;
          final nextLine = i + 1 < lines.length ? lines[i + 1] : null;
          if (nextLine != null && !nextLine.startsWith('#')) {
            final variantUrl = nextLine.startsWith('http') ? nextLine : m3u8Url.substring(0, m3u8Url.lastIndexOf("/") + 1) + nextLine;
            variantStreams.add({'url': variantUrl, 'bandwidth': bandwidth.toString()});
          }
        }
      }

      if (variantStreams.isEmpty) {
        throw Exception('Không tìm thấy variant stream trong master playlist: $m3u8Url');
      }

      variantStreams.sort((a, b) => int.parse(b['bandwidth']!).compareTo(int.parse(a['bandwidth']!)));
      final selectedVariantUrl = variantStreams.first['url']!;

      return await _parseM3U8(selectedVariantUrl, saveDir);
    }

    String? keyUrl;
    for (var line in lines) {
      if (line.startsWith('#EXT-X-KEY')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (match != null) {
          keyUrl = match.group(1)!;
          if (!keyUrl.startsWith('http')) {
            keyUrl = m3u8Url.substring(0, m3u8Url.lastIndexOf("/") + 1) + keyUrl;
          }
        }
      }
    }

    if (!lines.contains('#EXT-X-ENDLIST')) {
      //updateStatus('⚠️ Cảnh báo: Đây là live stream, chỉ tải các segment hiện tại');
    }

    final segments = lines.where((l) => l.trim().contains('.ts') || l.trim().contains('.mp4')).toList();
    if (segments.isEmpty) {
      throw Exception('Không tìm thấy segment .ts trong $m3u8Url');
    }

    List<Map<String, String>> jobs = [];
    for (int i = 0; i < segments.length; i++) {
      final segUrl = segments[i].startsWith('http') ? segments[i] : baseUrl + segments[i];
      final path = '$saveDir/seg_${i.toString().padLeft(4, '0')}.ts';
      jobs.add({'url': segUrl, 'path': path, 'retries': '0'});
    }

    if (keyUrl != null) {
      final keyPath = '$saveDir/key.key';
      try {
        await dio.download(keyUrl, keyPath, cancelToken: _cancelToken);
        jobs.add({'keyPath': keyPath});
        //updateStatus('🔐 Đã tải encryption key từ $keyUrl');
      } catch (e) {
        throw Exception('Lỗi tải encryption key từ $keyUrl: $e');
      }
    }

    return jobs;*/
  }

  Future<void> _downloadInBatches(List<Map<String, dynamic>> jobs, {int batchSize = 10, required bool isVideo}) async {
    while (jobs.isNotEmpty && !_cancelToken.isCancelled) {
      final batch = jobs.take(batchSize).toList();
      jobs.removeRange(0, batch.length);

      final futures = batch.where((job) => job.containsKey('segment')).map((job) => _downloadSegment(job, isVideo));
      await Future.wait(futures);

      if (isPaused) break;
    }
  }

  Future<void> _downloadSegment(Map<String, dynamic> job, bool isVideo) async {
    final segment = job['segment'] as Segment;
    final path = job['path'];
    final baseUrl = job['base_url'];
    final retries = int.parse(job['retries']);

    try {
      if (_cancelToken.isCancelled) return;

      final file = File(path);
      debugPrint(p.basename(file.path));
      if (!await file.exists()) {
        debugPrint('${DateTime.now().toString()} Tải ${p.basename(file.path)}');
        // Xóa để tránh ghi nối vào file cũ
        final tempPath = '$path.tmp';
        if (File(tempPath).existsSync()) {
          File(tempPath).deleteSync();
        }

        // Nếu initilization segment tồn tại, tải nó trước

        if (segment.initializationSegment != null) {
          final segUrl = segment.initializationSegment!.url!.startsWith('http') ? segment.initializationSegment!.url! : baseUrl + segment.initializationSegment!.url!;
          await dio.download(
            segUrl!,
            tempPath,
            fileAccessMode: FileAccessMode.write,
            cancelToken: _cancelToken,
            options: Options(
              headers: {
                'Range':
                    'bytes=${segment.initializationSegment!.byterangeOffset}-${segment.initializationSegment!.byterangeOffset! + segment.initializationSegment!.byterangeLength! - 1}',
              },
            ),
          );
        }

        final segUrl = segment.url!.startsWith('http') ? segment.url! : baseUrl + segment.url!;
        await dio.download(
          segUrl!,
          tempPath,
          fileAccessMode: FileAccessMode.append,
          cancelToken: _cancelToken,
          options: segment.byterangeOffset != null
              ? Options(headers: {'Range': 'bytes=${segment.byterangeOffset}-${segment.byterangeOffset! + segment.byterangeLength! - 1}'})
              : null,
        );
        await File(tempPath).rename(path);
      } else {
        debugPrint('${DateTime.now().toString()} Segment đã tồn tại: ${p.basename(file.path)}');
      }

      if (isVideo) {
        videoDownloaded++;
      } else {
        audioDownloaded++;
      }

      updateProgress();
    } catch (e) {
      if (!_cancelToken.isCancelled) {
        if (retries < maxRetries) {
          debugPrint('${DateTime.now().toString()} Retry lần ${retries + 1} với segment: ${segment.url}');
          await Future.delayed(Duration(seconds: 1));

          final retryJob = {'segment': segment, 'path': job['path']!, 'index': job['index']!, 'base_url': baseUrl, 'retries': (retries + 1).toString()};
          await Future.delayed(Duration(seconds: 3));

          if (isVideo) {
            videoJobs.insert(0, retryJob);
          } else {
            audioJobs.insert(0, retryJob);
          }
        } else {
          debugPrint('${DateTime.now().toString()} Thất bại sau $maxRetries lần retry: ${segment.url}');
          statusController.add(DownloadStatus.FAILED);
          _cancelToken.cancel();
        }
      }
    }
  }

  Future<void> _mergeVideoAudio(String fileName, String? videoUrl, String? audioUrl) async {
    try {
      String outputPath = '${workingDir.path}/$fileName';
      String? keyPath = videoJobs.firstWhere((job) => job.containsKey('keyPath'), orElse: () => {})['keyPath'];

      String ffmpegCommand = '';
      String mergedVideoTs = '';
      String mergedAudioTs = '';
      // Merge segment của video
      if (videoUrl != null) {
        final videoListFile = File('${videoDir.path}/file_list.txt');
        final videoFiles = videoDir.listSync().whereType<File>().where((f) => f.path.endsWith('.ts')).toList()..sort((a, b) => a.path.compareTo(b.path));
        final videoListContent = videoFiles.map((f) => "file '${f.path}'").join('\n');
        await videoListFile.writeAsString(videoListContent);
        mergedVideoTs = '${videoDir.path}/merged.ts';
        await FFmpegKit.execute('-f concat -safe 0 -i ${videoListFile.path} -c copy $mergedVideoTs');
      }

      if (audioUrl != null) {
        final audioListFile = File('${audioDir.path}/file_list.txt');
        final audioFiles = audioDir.listSync().whereType<File>().where((f) => f.path.endsWith('.ts')).toList()..sort((a, b) => a.path.compareTo(b.path));
        final audioListContent = audioFiles.map((f) => "file '${f.path}'").join('\n');
        await audioListFile.writeAsString(audioListContent);
        mergedAudioTs = '${audioDir.path}/merged.ts';
        await FFmpegKit.execute('-f concat -safe 0 -i ${audioListFile.path} -c copy $mergedAudioTs');
      }

      if (videoUrl != null && audioUrl != null) {
        // Nếu cả video và audio cùng tồn tại, merge cả 2 lại
        ffmpegCommand = '-y -i $mergedVideoTs -i $mergedAudioTs -c:v copy -c:a copy -async 1 -preset ultrafast $outputPath';
      } else {
        // Nếu có 1 trong 2, chuyển nó sang output cuối cùng
        var mergeTs = mergedVideoTs + mergedAudioTs;
        ffmpegCommand = '-y -i $mergeTs -c copy -preset ultrafast $outputPath';
      }
      debugPrint(ffmpegCommand);
      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        statusController.add(DownloadStatus.DOWNLOADED);
        await _cleanup();
      } else {
        final logs = await session.getLogs();
        statusController.add(DownloadStatus.FAILED);
      }
    } catch (e) {
      statusController.add(DownloadStatus.FAILED);
    }
  }

  Future<void> _cleanup() async {
    if (await videoDir.exists()) await videoDir.delete(recursive: true);
    if (await audioDir.exists()) await audioDir.delete(recursive: true);
  }

  @override
  void pauseDownload() {
    _cancelToken.cancel();
    isPaused = true;
    statusController.add(DownloadStatus.PAUSED);
  }

  @override
  void resumeDownload() {
    startDownload(isResume: true);
  }

  @override
  void stopDownload() {
    _cancelToken.cancel();
    reset();
  }

  void updateProgress() {
    final totalDownloaded = videoDownloaded + audioDownloaded;
    final totalSegments = videoTotal + audioTotal;
    currentProgress = totalSegments > 0 ? totalDownloaded / totalSegments : 0;
    if ((currentProgress - lastReportedProgress) >= (progressUpdateStep / 100)) {
      progressController.add(currentProgress);
      lastReportedProgress = currentProgress;
    }
  }

  void reset() {
    videoJobs.clear();
    audioJobs.clear();
    videoDownloaded = 0;
    audioDownloaded = 0;
    videoTotal = 1;
    audioTotal = 0;
    currentProgress = 0;
    isPaused = false;
  }

  void dispose() {
    progressController.close();
    statusController.close();
  }
}
