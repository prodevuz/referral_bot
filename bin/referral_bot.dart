import 'dart:io';
import 'package:referral_bot/exceptions/bot_exception.dart';
import 'package:referral_bot/referral_bot.dart';
import 'package:teledart/telegram.dart';

void main() async {
  try {
    final token = Platform.environment['BOT_TOKEN'];
    if (token == null) {
      throw BotException('Failed to get bot token');
    }

    final telegram = Telegram(token);
    
    final username = (await telegram.getMe()).username;

    if (username == null) {
      throw BotException('Failed to get bot username');
    }

    print('Starting the bot...');
    final bot = ReferralBot(token, username);
    await bot.init();
    print('Bot initialized and running.');
  } catch (e, stackTrace) {
    print('Fatal error: $e\n$stackTrace');
    exit(1);
  }
}
