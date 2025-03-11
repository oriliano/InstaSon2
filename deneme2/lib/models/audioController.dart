import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioController extends GetxController {
  final _isRecordPlaying = RxBool(false);
  final isRecording = RxBool(false);
  final isSending = RxBool(false);
  final isUploading = RxBool(false);
  final _currentId = RxInt(999999);
  final start = Rx<DateTime>(DateTime.now());
  final end = Rx<DateTime>(DateTime.now());
  String _total = "";
  String get total => _total;
  final completedPercentage = RxDouble(0.0);
  final currentDuration = RxInt(0);
  final totalDuration = RxInt(0);

  bool get isRecordPlaying => _isRecordPlaying.value;
  bool get isRecordingValue => isRecording.value;
  late final AudioPlayerService _audioPlayerService;
  int get currentId => _currentId.value;

  @override
  void onInit() {
    super.onInit();
    _audioPlayerService = AudioPlayerAdapter();
    _initAudioListeners();
  }

  void _initAudioListeners() {
    _audioPlayerService.getAudioPlayer.onDurationChanged.listen(
      (duration) {
        totalDuration.value = duration.inMicroseconds;
      },
      onError: (error) {
        print('Duration error: $error');
      },
      cancelOnError: false,
    );

    _audioPlayerService.getAudioPlayer.onPositionChanged.listen(
      (duration) {
        if (totalDuration.value > 0) {
          currentDuration.value = duration.inMicroseconds;
          completedPercentage.value =
              currentDuration.value.toDouble() / totalDuration.value.toDouble();
        }
      },
      onError: (error) {
        print('Position error: $error');
      },
      cancelOnError: false,
    );

    _audioPlayerService.getAudioPlayer.onPlayerComplete.listen(
      (event) async {
        await _audioPlayerService.getAudioPlayer.seek(Duration.zero);
        _isRecordPlaying.value = false;
      },
      onError: (error) {
        print('Player complete error: $error');
      },
      cancelOnError: false,
    );
  }

  @override
  void onClose() {
    _audioPlayerService.dispose();
    super.onClose();
  }

  Future<void> changeProg() async {
    if (isRecordPlaying) {
      try {
        _audioPlayerService.getAudioPlayer.onDurationChanged.listen(
          (duration) {
            totalDuration.value = duration.inMicroseconds;
          },
          cancelOnError: false,
        );

        _audioPlayerService.getAudioPlayer.onPositionChanged.listen(
          (duration) {
            if (totalDuration.value > 0) {
              currentDuration.value = duration.inMicroseconds;
              completedPercentage.value = currentDuration.value.toDouble() /
                  totalDuration.value.toDouble();
            }
          },
          cancelOnError: false,
        );
      } catch (e) {
        print('Change progress error: $e');
      }
    }
  }

  void onPressedPlayButton(int id, String content) async {
    try {
      _currentId.value = id;
      if (isRecordPlaying) {
        await _pauseRecord();
      } else {
        _isRecordPlaying.value = true;
        await _audioPlayerService.play(content);
      }
    } catch (e) {
      print('Play button error: $e');
      _isRecordPlaying.value = false;
    }
  }

  calcDuration() {
    var a = end.value.difference(start.value).inSeconds;
    format(Duration d) => d.toString().split('.').first.padLeft(8, "0");
    _total = format(Duration(seconds: a));
  }

  Future<void> _pauseRecord() async {
    try {
      _isRecordPlaying.value = false;
      await _audioPlayerService.pause();
    } catch (e) {
      print('Pause record error: $e');
    }
  }
}

abstract class AudioPlayerService {
  void dispose();
  Future<void> play(String url);
  Future<void> resume();
  Future<void> pause();
  Future<void> release();

  AudioPlayer get getAudioPlayer;
}

class AudioPlayerAdapter implements AudioPlayerService {
  late AudioPlayer _audioPlayer;

  @override
  AudioPlayer get getAudioPlayer => _audioPlayer;

  AudioPlayerAdapter() {
    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() async {
    try {
      await _audioPlayer.dispose();
    } catch (e) {
      print('Dispose error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      print('Pause error: $e');
    }
  }

  @override
  Future<void> play(String url) async {
    try {
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      print('Play error: $e');
    }
  }

  @override
  Future<void> release() async {
    try {
      await _audioPlayer.release();
    } catch (e) {
      print('Release error: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      print('Resume error: $e');
    }
  }
}

class AudioDuration {
  static double calculate(Duration soundDuration) {
    if (soundDuration.inSeconds > 60) {
      return 70.0.w;
    } else if (soundDuration.inSeconds > 50) {
      return 65.0.w;
    } else if (soundDuration.inSeconds > 40) {
      return 60.0.w;
    } else if (soundDuration.inSeconds > 30) {
      return 55.0.w;
    } else if (soundDuration.inSeconds > 20) {
      return 50.0.w;
    } else if (soundDuration.inSeconds > 10) {
      return 45.0.w;
    } else {
      return 40.0.w;
    }
  }
}
