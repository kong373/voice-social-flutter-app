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
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF21184D),
            Color(0xFF101936),
            Color(0xFF080D22),
            AppColors.background,
          ],
          stops: <double>[0, 0.32, 0.68, 1],
        ).createShader(rect),
    );

    final Paint glow = Paint()
      ..shader =
          RadialGradient(
            colors: <Color>[
              AppColors.primary.withValues(alpha: 0.33),
              AppColors.primary.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.72, size.height * 0.15),
              radius: size.width * 0.62,
            ),
          );
    canvas.drawRect(rect, glow);

    final Paint moon = Paint()
      ..shader =
          const RadialGradient(
            colors: <Color>[Color(0xFFF5EEFF), Color(0xFF9B7BFF)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.82, size.height * 0.105),
              radius: 44,
            ),
          );
    canvas.drawCircle(Offset(size.width * 0.82, size.height * 0.105), 28, moon);

    final Paint star = Paint()..color = Colors.white.withValues(alpha: 0.42);
    for (int index = 0; index < 36; index += 1) {
      final double x = ((index * 73) % 101) / 101 * size.width;
      final double y = ((index * 47) % 89) / 89 * size.height * 0.38;
      canvas.drawCircle(Offset(x, y), index % 5 == 0 ? 1.3 : 0.65, star);
    }

    final Path haze = Path()
      ..moveTo(0, size.height * 0.42)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.34,
        size.width * 0.48,
        size.height * 0.50,
        size.width * 0.78,
        size.height * 0.40,
      )
      ..cubicTo(
        size.width * 0.90,
        size.height * 0.36,
        size.width,
        size.height * 0.42,
        size.width,
        size.height * 0.42,
      )
      ..lineTo(size.width, size.height * 0.62)
      ..lineTo(0, size.height * 0.62)
      ..close();
    canvas.drawPath(
      haze,
      Paint()..color = AppColors.accent.withValues(alpha: 0.045),
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
    final Color ringColor = speaking
        ? AppColors.success
        : occupied
        ? AppColors.primaryBright
        : Colors.white.withValues(alpha: 0.15);
    final IconData stateIcon = switch (seat.state) {
      MicSeatState.locked => Icons.lock_rounded,
      MicSeatState.mutedAvailable => Icons.mic_off_rounded,
      MicSeatState.occupiedMuted => Icons.mic_off_rounded,
      MicSeatState.available => Icons.add_rounded,
      MicSeatState.occupied => Icons.mic_rounded,
    };
    final List<Color> avatarColors = seat.number.isEven
        ? const <Color>[AppColors.primary, AppColors.accent]
        : const <Color>[AppColors.secondary, AppColors.primary];

    return Semantics(
      label: '${seat.number} 号麦，${seat.userName ?? _seatStatus(seat.state)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 8, 5, 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: occupied ? 0.055 : 0.026),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: speaking
                ? AppColors.success.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.055),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: occupied
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: avatarColors,
                      )
                    : null,
                color: occupied ? null : Colors.white.withValues(alpha: 0.045),
                border: Border.all(color: ringColor, width: speaking ? 3 : 1.5),
                boxShadow: speaking
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.36),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(
                    occupied ? Icons.person_rounded : stateIcon,
                    color: occupied ? Colors.white : AppColors.textSecondary,
                    size: occupied ? 28 : 22,
                  ),
                  if (occupied)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: seat.state == MicSeatState.occupiedMuted
                              ? AppColors.error
                              : AppColors.surfaceHighest,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.backgroundElevated,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          seat.state == MicSeatState.occupiedMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
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
            const SizedBox(height: 2),
            Text(
              speaking ? '正在说话' : _seatStatus(seat.state),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: speaking ? AppColors.success : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _seatStatus(MicSeatState state) {
    return switch (state) {
      MicSeatState.available => '空闲',
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
      radius: 34,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: enabled
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          AppColors.primary.withValues(alpha: 0.26),
                          AppColors.surfaceHighest.withValues(alpha: 0.86),
                        ],
                      )
                    : null,
                color: enabled ? null : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: enabled
                      ? AppColors.primary.withValues(alpha: 0.26)
                      : Colors.white.withValues(alpha: 0.045),
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
                fontWeight: FontWeight.w650,
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
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.32),
            ),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 30,
                  color: AppColors.warning,
                ),
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
