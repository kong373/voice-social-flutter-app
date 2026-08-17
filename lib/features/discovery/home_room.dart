class HomeRoom {
  const HomeRoom({
    required this.id,
    required this.title,
    required this.topic,
    required this.listeners,
    required this.occupiedSeats,
    required this.friendReason,
    required this.isSpeaking,
  });

  final String id;
  final String title;
  final String topic;
  final int listeners;
  final int occupiedSeats;
  final String friendReason;
  final bool isSpeaking;
}
