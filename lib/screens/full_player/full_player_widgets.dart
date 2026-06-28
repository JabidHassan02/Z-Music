import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:marquee/marquee.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

class FullPlayerSongHeader extends StatelessWidget {
  final SongModel song;

  const FullPlayerSongHeader({
    super.key,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 36,
          width: MediaQuery.of(context).size.width * 0.8,
          child: Marquee(
            key: ValueKey(song.id),
            text: song.title,
            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700),
            scrollAxis: Axis.horizontal,
            blankSpace: 42,
            velocity: 26,
            pauseAfterRound: const Duration(milliseconds: 900),
          ),
        ),
        Text(
          song.artist ?? 'Unknown Artist',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}

class FullPlayerProgressSection extends StatelessWidget {
  final AudioPlayer audioPlayer;
  final Color accentColor;
  final double sliderSize;
  final SongModel song;
  final String Function(Duration, Duration) formatProgress;

  const FullPlayerProgressSection({
    super.key,
    required this.audioPlayer,
    required this.accentColor,
    this.sliderSize = 250,
    required this.song,
    required this.formatProgress,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: audioPlayer.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? const Duration(seconds: 1);
        return StreamBuilder<Duration>(
          stream: audioPlayer.positionStream,
          builder: (context, positionSnapshot) {
            var position = positionSnapshot.data ?? Duration.zero;
            if (position > duration) position = duration;
            final discSize = sliderSize * (188 / 250);

            return StreamBuilder<PlayerState>(
              stream: audioPlayer.playerStateStream,
              builder: (context, playerStateSnapshot) {
                final isPlaying =
                    playerStateSnapshot.data?.playing ?? audioPlayer.playing;

                return Column(
                  children: [
                    SleekCircularSlider(
                      min: 0,
                      max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                      initialValue: position.inSeconds.toDouble(),
                      onChangeEnd: (value) => audioPlayer.seek(Duration(seconds: value.toInt())),
                      appearance: CircularSliderAppearance(
                        animationEnabled: false,
                        size: sliderSize,
                        startAngle: 140,
                        angleRange: 260,
                        customWidths: CustomSliderWidths(
                          trackWidth: 5,
                          progressBarWidth: 7,
                          handlerSize: 9,
                        ),
                        customColors: CustomSliderColors(
                          trackColor: Colors.white24,
                          progressBarColor: accentColor,
                          dotColor: Colors.white,
                          hideShadow: true,
                        ),
                      ),
                      innerWidget: (_) {
                        return Center(
                          child: _RotatingArtworkDisc(
                            song: song,
                            isPlaying: isPlaying,
                            size: discSize,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatProgress(position, duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RotatingArtworkDisc extends StatefulWidget {
  final SongModel song;
  final bool isPlaying;
  final double size;

  const _RotatingArtworkDisc({
    required this.song,
    required this.isPlaying,
    required this.size,
  });

  @override
  State<_RotatingArtworkDisc> createState() => _RotatingArtworkDiscState();
}

class _RotatingArtworkDiscState extends State<_RotatingArtworkDisc>
    with SingleTickerProviderStateMixin {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RotatingArtworkDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _rotationController
        ..stop()
        ..value = 0;
      if (widget.isPlaying) {
        _rotationController.repeat();
      }
      return;
    }

    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hubSize = widget.size * 0.34;
    final iconSize = hubSize * 0.52;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _rotationController,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF121212),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 18,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
              child: ClipOval(
                child: QueryArtworkWidget(
                  controller: _audioQuery,
                  id: widget.song.id,
                  type: ArtworkType.AUDIO,
                  format: ArtworkFormat.JPEG,
                  quality: 80,
                  size: 512,
                  keepOldArtwork: true,
                  artworkQuality: FilterQuality.medium,
                  artworkFit: BoxFit.cover,
                  nullArtworkWidget: Container(
                    color: const Color(0xFF121212),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: hubSize,
            height: hubSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0E0E0E).withValues(alpha: 0.9),
              border: Border.all(color: Colors.white12, width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              Icons.music_note,
              size: iconSize,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class FullPlayerActionButtonsRow extends StatelessWidget {
  final bool isFavorite;
  final LoopMode loopMode;
  final Color accentColor;
  final VoidCallback onFavorite;
  final VoidCallback onTheme;
  final VoidCallback onSleep;
  final VoidCallback onMore;
  final VoidCallback onRepeat;

  const FullPlayerActionButtonsRow({
    super.key,
    required this.isFavorite,
    required this.loopMode,
    required this.accentColor,
    required this.onFavorite,
    required this.onTheme,
    required this.onSleep,
    required this.onMore,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.pinkAccent : Colors.white70,
              size: 24,
            ),
            onPressed: onFavorite,
          ),
          IconButton(
            icon: Icon(Icons.palette_outlined, color: accentColor, size: 24),
            onPressed: onTheme,
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined, color: Colors.white70, size: 24),
            onPressed: onSleep,
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white70, size: 26),
            onPressed: onMore,
          ),
          IconButton(
            icon: Icon(
              loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
              color: loopMode == LoopMode.off ? Colors.white70 : accentColor,
              size: 24,
            ),
            onPressed: onRepeat,
          ),
        ],
      ),
    );
  }
}

class FullPlayerTransportControls extends StatelessWidget {
  final AudioPlayer audioPlayer;
  final Color accentColor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final void Function(int seconds) onSkip;

  const FullPlayerTransportControls({
    super.key,
    required this.audioPlayer,
    required this.accentColor,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 32, top: 8),
      child: StreamBuilder<PlayerState>(
        stream: audioPlayer.playerStateStream,
        builder: (context, snapshot) {
          final isPlaying = snapshot.data?.playing ?? false;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white70, size: 28),
                onPressed: () => onSkip(-10),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white, size: 34),
                onPressed: onPrevious,
              ),
              GestureDetector(
                onTap: () => isPlaying ? audioPlayer.pause() : audioPlayer.play(),
                child: Container(
                  height: 60,
                  width: 60,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white, size: 34),
                onPressed: onNext,
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white70, size: 28),
                onPressed: () => onSkip(10),
              ),
            ],
          );
        },
      ),
    );
  }
}
