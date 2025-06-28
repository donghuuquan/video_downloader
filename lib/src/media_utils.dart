import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';

class MediaUtils {
  static Future<String> getAudioExtentionFromUrl(String url, {String defaultExt = 'mp3'}) async {
    var mediaInfo = await FFprobeKit.getMediaInformation(url);
    final information = mediaInfo.getMediaInformation();
    if (information == null) {
      // Show error, stop translate process
      throw Exception();
    }
    return getAudioStreamExtensions(information.getStreams(), defaultExt: defaultExt);
  }

  static String getAudioStreamExtensions(List<StreamInformation> streams, {String defaultExt = 'mp3'}) {
    for (var stream in streams) {
      if (stream.getType() == 'audio') {
        String fileExtension;
        switch (stream.getCodec()) {
          case 'aac':
            fileExtension = 'm4a'; // AAC thường dùng phần mở rộng .m4a
            break;
          case 'mp3':
            fileExtension = 'mp3'; // MP3 luôn luôn có phần mở rộng .mp3
            break;
          case 'vorbis':
            fileExtension = 'ogg'; // Vorbis thường dùng .ogg (hoặc .oga cho audio)
            break;
          case 'opus':
            fileExtension = 'opus'; // Opus có phần mở rộng .opus
            break;
          case 'flac':
            fileExtension = 'flac'; // FLAC có phần mở rộng .flac
            break;
          case 'wav':
          case 'pcm_s16le':
          case 'pcm_u8':
          case 'pcm_s24le':
          case 'pcm_f32le':
            fileExtension = 'wav'; // WAV (chứa PCM) có phần mở rộng .wav
            break;
          case 'alac':
            fileExtension = 'm4a'; // ALAC thường dùng phần mở rộng .m4a
            break;
          case 'wma':
            fileExtension = 'wma'; // Windows Media Audio có phần mở rộng .wma
            break;
          case 'ac3':
            fileExtension = 'ac3'; // Dolby Digital Audio có phần mở rộng .ac3
            break;
          case 'eac3':
            fileExtension = 'eac3'; // Dolby Digital Plus có phần mở rộng .eac3
            break;
          default:
            fileExtension = defaultExt; // Mặc định là mp3 nếu không xác định được codec
        }

        return fileExtension;
      }
    }
    return '';
  }

  static Future<String> getVideoExtentionFromUrl(String url) async {
    final audioSession = await FFprobeKit.getMediaInformation(url);
    final videoInfo = audioSession.getMediaInformation();

    if (videoInfo == null) {
      // Show error, stop translate process
      throw Exception('Could not retrieve video information');
    }
    return getVideoStreamExtensions(videoInfo.getStreams());
  }

  static String getVideoStreamExtensions(List<StreamInformation> streams) {
    for (var stream in streams) {
      if (stream.getType() == 'video') {
        String codec = stream.getCodec() ?? '';
        final codecExtensionMap = {
          'h264': 'mp4',
          'avc1': 'mp4',
          'hevc': 'mkv',
          'mpeg4': 'mp4',
          'theora': 'ogv',
          'av1': 'mkv',
          'wmv3': 'wmv',
          'mpeg2': 'mpg',
        };

        return codecExtensionMap[codec.toLowerCase()] ?? 'mp4';
      }
    }
    return 'mp4'; // Mặc định trả về .mp4 nếu không tìm thấy codec video
  }
}
