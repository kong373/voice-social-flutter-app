part of 'room_page.dart';

class _RoomBackground extends StatelessWidget {
  const _RoomBackground();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _RoomSkyPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _RoomSkyPainter extends CustomPainter {
  const _RoomSkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = AppColors.roomGradient.createShader(rect),
    );

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            AppColors.primary.withValues(alpha: 0.34),
            AppColors.primary.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.73, size.height * 0.15),
            radius: size.width * 0.64,
          ),
        ),
    );

    final Offset moonCenter = Offset(size.width * 0.82, size.height * 0.105);
    canvas.drawCircle(
      moonCenter,
      28,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0xFFF7F0FF), Color(0xFF9B7BFF)],
        ).createShader(Rect.fromCircle(center: moonCenter, radius: 44)),
    );

    final Paint star = Paint()..color = Colors.white.withValues(alpha: 0.48);
    for (int index = 0; index < 40; index += 1) {
      final double x = ((index * 73) % 101) / 101 * size.width;
      final double y = ((index * 47) % 89) / 89 * size.height * 0.40;
      canvas.drawCircle(Offset(x, y), index % 5 == 0 ? 1.35 : 0.68, star);
    }

    final Path haze = Path()
      ..moveTo(0, size.height * 0.43)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.34,
        size.width * 0.47,
        size.height * 0.51,
        size.width * 0.76,
        size.height * 0.41,
      )
      ..cubicTo(
        size.width * 0.91,
        size.height * 0.35,
        size.width,
        size.height * 0.43,
        size.width,
        size.height * 0.43,
      )
      ..lineTo(size.width, size.height * 0.63)
      ..lineTo(0, size.height * 0.63)
      ..close();
    canvas.drawPath(
      haze,
      Paint()..color = AppColors.accent.withValues(alpha: 0.05),
    );
  }

  @override
  bool shouldRepaint(covariant _RoomSkyPainter oldDelegate) => false;
}

class _MicSeatTile extends StatelessWidget {
  const _MicSeatTile({required this.seat});

  final MicSeat seat;

  @override
  Widget build(BuildContext context) {
    final bool occupied = seat.userName != null;
    final bool speaking = seat.isSpeaking;
    final bool muted = seat.state == MicSeatState.occupiedMuted;
    final Color ringColor = speaking
        ? AppColors.success
        : occupied
            ? AppColors.primaryBright
            : seat.state == MicSeatState.locked
                ? AppColors.gold
                : Colors.white.withValues(alpha: 0.22);
    final IconData emptyIcon = switch (seat.state) {
      MicSeatState.locked => Icons.lock_rounded,
      MicSeatState.mutedAvailable => Icons.mic_off_rounded,
      MicSeatState.available => Icons.add_rounded,
      MicSeatState.occupied || MicSeatState.occupiedMuted => Icons.person_rounded,
    };
    final List<Color> avatarColors = seat.number.isEven
        ? const <Color>[AppColors.primary, AppColors.accent]
        : const <Color>[AppColors.secondary, AppColors.primary];

    return Semantics(
      label: '${seat.number} 号麦，${seat.userName ?? _seatStatus(seat.state)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: occupied
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: avatarColors,
                    )
                  : null,
              color: occupied ? null : Colors.white.withValues(alpha: 0.055),
              border: Border.all(
                color: ringColor,
                width: speaking ? 3 : 1.8,
              ),
              boxShadow: <BoxShadow>[
                if (speaking)
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.42),
                    blurRadius: 22,
                    spreadRadius: 1,
                  )
                else if (occupied)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.20),
                    blurRadius: 14,
                  ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(
                  occupied ? Icons.person_rounded : emptyIcon,
                  color: occupied ? Colors.white : ringColor,
                  size: occupied ? 29 : 22,
                ),
                if (occupied)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: BoxDecoration(
                        color: muted ? AppColors.error : AppColors.surfaceHighest,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.backgroundElevated,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  left: -2,
                  top: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: seat.number == 1
                          ? AppColors.gold
                          : AppColors.surfaceHighest.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${seat.number}',
                      style: TextStyle(
                        color: seat.number == 1
                            ? const Color(0xFF4D3210)
                            : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (seat.number == 1) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '房主',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  seat.userName ?? '${seat.number} 号麦',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: occupied
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: occupied ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: speaking
                ? const VoiceWave(key: ValueKey<String>('speaking'), width: 30)
                : Text(
                    _seatStatus(seat.state),
                    key: ValueKey<MicSeatState>(seat.state),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
          ),
        ],
      ),
    );
  }

  String _seatStatus(MicSeatState state) {
    return switch (state) {
      MicSeatState.available => '点击上麦',
      MicSeatState.locked => '已锁定',
      MicSeatState.mutedAvailable => '空麦闭麦',
      MicSeatState.occupied => '麦上',
      MicSeatState.occupiedMuted => '已静音',
    };
  }
}

class _RoomAction extends StatelessWidget {
  const _RoomAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 32,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.035),
                shape: BoxShape.circle,
                border: Border.all(
                  color: enabled
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.045),
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 58, left: 18, right: 18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighest.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.32)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.wifi_tethering_error_rounded,
                size: 17,
                color: AppColors.warning,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockingProgress extends StatelessWidget {
  const _BlockingProgress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.56),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(30),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteExitOverlay extends StatelessWidget {
  const _RemoteExitOverlay({
    required this.title,
    required this.message,
    required this.onExit,
  });

  final String title;
  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          width: 320,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.surfaceHighest, AppColors.surface],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.info_outline_rounded,
                size: 32,
                color: AppColors.warning,
              ),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onExit,
                  child: const Text('返回首页'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
