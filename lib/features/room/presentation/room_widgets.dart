part of 'room_page.dart';

class _RoomBackground extends StatelessWidget {
  const _RoomBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF191334),
            Color(0xFF0D1020),
            AppColors.background,
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _MicSeatTile extends StatelessWidget {
  const _MicSeatTile({required this.seat});

  final MicSeat seat;

  @override
  Widget build(BuildContext context) {
    final bool occupied = seat.userName != null;
    final Color ringColor = seat.isSpeaking
        ? AppColors.success
        : occupied
        ? AppColors.primary
        : Colors.white.withValues(alpha: 0.16);
    final IconData stateIcon = switch (seat.state) {
      MicSeatState.locked => Icons.lock_rounded,
      MicSeatState.mutedAvailable => Icons.mic_off_rounded,
      MicSeatState.occupiedMuted => Icons.mic_off_rounded,
      MicSeatState.available => Icons.add_rounded,
      MicSeatState.occupied => Icons.mic_rounded,
    };

    return Semantics(
      label: '${seat.number} 号麦，${seat.userName ?? _seatStatus(seat.state)}',
      child: Column(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: occupied
                  ? AppColors.surfaceHigh
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: ringColor,
                width: seat.isSpeaking ? 3 : 1.5,
              ),
              boxShadow: seat.isSpeaking
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.25),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              occupied ? Icons.person_rounded : stateIcon,
              color: occupied ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            seat.userName ?? '${seat.number} 号麦',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Icon(stateIcon, size: 14, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  String _seatStatus(MicSeatState state) {
    return switch (state) {
      MicSeatState.available => '空闲',
      MicSeatState.locked => '已锁定',
      MicSeatState.mutedAvailable => '空麦且闭麦',
      MicSeatState.occupied => '已占用',
      MicSeatState.occupiedMuted => '已占用且闭麦',
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
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.04),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Icon(
                icon,
                size: 22,
                color: enabled ? null : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
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
          margin: const EdgeInsets.only(top: 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.warning,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
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
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(label),
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
      color: Colors.black.withValues(alpha: 0.68),
      child: Center(
        child: Container(
          width: 310,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.info_outline_rounded,
                size: 36,
                color: AppColors.warning,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
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
