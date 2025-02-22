/// Custom exception for bot-related errors
class BotException implements Exception {
  final String message;
  BotException(this.message);

  @override
  String toString() => 'BotException: $message';
}
