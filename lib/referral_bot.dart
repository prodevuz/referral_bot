import 'dart:convert';
import 'dart:io';

import 'package:teledart/model.dart' hide File, User;
import 'package:teledart/teledart.dart';

import 'exceptions/bot_exception.dart';
import 'models/config_model.dart';
import 'models/user_model.dart';
import 'utils/debouncer.dart';

export 'package:referral_bot/models/user_model.dart';

class ReferralBot {
  final String token;
  final String username;
  final TeleDart teledart;
  late final String storageFilePath;
  late final String configFilePath;
  final Map<String, User> _users = {};
  late Config _config;
  final _saveDebouncer = Debouncer(Duration(seconds: 5));

  ReferralBot(this.token, this.username) : teledart = TeleDart(token, Event(username));

  Future<void> init() async {
    try {
      storageFilePath = 'assets/referrals.json';
      configFilePath = 'assets/config.json';
      _createStorageDirectoryIfNeeded();
      await _loadConfig();
      await _loadUsers();

      teledart.start();
      _setupListeners();

      print('Bot initialized successfully.');
    } catch (e, stackTrace) {
      print('Error during bot initialization: $e\n$stackTrace');
      throw BotException('Failed to initialize bot: $e');
    }
  }

  void _createStorageDirectoryIfNeeded() {
    final directory = Directory('assets');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  Future<void> _loadConfig() async {
    try {
      final file = File(configFilePath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.isNotEmpty) {
          _config = Config.fromJson(json.decode(jsonString));
          return;
        }
      }
      _config = Config.defaultConfig();
      await _saveConfig();
    } catch (e) {
      print('Error loading config: $e');
      _config = Config.defaultConfig();
    }
  }

  Future<void> _saveConfig() async {
    try {
      await File(configFilePath).writeAsString(json.encode(_config.toJson()));
    } catch (e) {
      print('Error saving config: $e');
    }
  }

  Future<void> _loadUsers() async {
    try {
      final file = File(storageFilePath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.isEmpty) return;

        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        _users.clear();
        _users.addAll(jsonMap.map((key, value) => MapEntry(key, User.fromJson(value as Map<String, dynamic>))));
        print('Loaded ${_users.length} users from storage.');
      }
    } catch (e, stackTrace) {
      print('Error loading users: $e\n$stackTrace');
      throw BotException('Failed to load users: $e');
    }
  }

  Future<void> _saveUsers() async {
    try {
      final jsonString = json.encode(_users.map((key, value) => MapEntry(key, value.toJson())));
      await File(storageFilePath).writeAsString(jsonString);
    } catch (e, stackTrace) {
      print('Error saving users: $e\n$stackTrace');
      throw BotException('Failed to save users: $e');
    }
  }

  void _setupListeners() {
    teledart.onMessage().listen(_handleMessage);
    teledart.onCommand('start').listen(_handleStartCommand);
    teledart.onCommand('stats').listen(_handleStatsCommand);
    teledart.onCommand('admin').listen(_handleAdminCommand);
    teledart.onCommand('link').listen(_handleLinkCommand);
    teledart.onCallbackQuery().listen(_handleCallbackQuery);
  }

  Future<bool> _checkSubscription(int userId) async {
    try {
      final chatMember = await teledart.getChatMember('@${_config.channelUsername}', userId);
      return ['creator', 'administrator', 'member'].contains(chatMember.status);
    } catch (e) {
      print('Error checking subscription status: $e');
      return false;
    }
  }

  bool _isAdmin(String userId) {
    return _config.adminIds.contains(userId);
  }

  Future<void> _handleAdminCommand(Message message) async {
    if (message.from == null) return;

    final userId = message.from!.id.toString();
    if (!_isAdmin(userId)) {
      await teledart.sendMessage(message.chat.id, 'You are not authorized to use admin commands.');
      return;
    }

    final args = message.text?.split(' ');
    if (args == null || args.length < 2) {
      await _sendAdminHelp(message.chat.id);
      return;
    }

    switch (args[1]) {
      case 'threshold':
        if (args.length == 3) {
          final threshold = int.tryParse(args[2]);
          if (threshold != null && threshold > 0) {
            _config.referralThreshold = threshold;
            await _saveConfig();
            await teledart.sendMessage(message.chat.id, 'Referral threshold updated to: $threshold');
            for (var user in _users.values) {
              if (user.referralCount >= _config.referralThreshold) {
                await _handleReferralThresholdReached(user.id);
              }
            }
          } else {
            await teledart.sendMessage(message.chat.id, 'Invalid threshold value. Please use a positive number.');
          }
        }
        break;

      case 'channel':
        if (args.length == 3) {
          final channel = args[2].replaceAll('@', '');
          _config.channelUsername = channel;
          await _saveConfig();
          await teledart.sendMessage(message.chat.id, 'Channel username updated to: @$channel');
        }
        break;

      case 'addadmin':
        if (args.length == 3) {
          final newAdminId = args[2];
          if (!_config.adminIds.contains(newAdminId)) {
            _config.adminIds.add(newAdminId);
            await _saveConfig();
            await teledart.sendMessage(message.chat.id, 'Admin added: $newAdminId');
          }
        }
        break;

      case 'removeadmin':
        if (args.length == 3) {
          final adminId = args[2];
          if (_config.adminIds.length > 1 && _config.adminIds.contains(adminId)) {
            _config.adminIds.remove(adminId);
            await _saveConfig();
            await teledart.sendMessage(message.chat.id, 'Admin removed: $adminId');
          }
        }
        break;

      case 'settings':
        await _sendAdminSettings(message.chat.id);
        break;

      case 'group':
        if (args.length == 3) {
          final groupLink = args[2];
          _config.privateGroupLink = groupLink;
          await _saveConfig();
          await teledart.sendMessage(message.chat.id, 'Private group link updated to: $groupLink');
        }
        break;

      default:
        await _sendAdminHelp(message.chat.id);
    }
  }

  Future<void> _handleLinkCommand(Message message) async {
    if (message.from == null) return;

    final userId = message.from!.id.toString();
    final user = _users[userId];

    if (user == null) {
      await teledart.sendMessage(message.chat.id, 'Siz hali do\'stlaringizni taklif qilmadingiz.');
      return;
    }

    if (user.referralCount < _config.referralThreshold) {
      await teledart.sendMessage(message.chat.id, 'Siz hali yetarlicha do\'st taklif qilmadingiz.');
      return;
    }

    await teledart.sendMessage(
      message.chat.id,
      '🎯 Marafonga qo\'shilish uchun maxfiy guruh havolasi:',
      replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
        [InlineKeyboardButton(text: '🎯 Maxfiy guruhga qo\'shilish', url: _config.privateGroupLink)]
      ]),
    );
  }

  Future<void> _sendAdminHelp(int chatId) async {
    await teledart.sendMessage(
      chatId,
      'Admin commands:\n'
      '/admin threshold <number> - Set referral threshold\n'
      '/admin channel <username> - Set channel username\n'
      '/admin group <link> - Set private group link\n'
      '/admin addadmin <user_id> - Add new admin\n'
      '/admin removeadmin <user_id> - Remove admin\n'
      '/admin settings - Show current settings',
    );
  }

  Future<void> _sendAdminSettings(int chatId) async {
    final admins = _config.adminIds.map((adminId) async => await teledart.getChat(adminId)).toList();
    final adminNames = await Future.wait(admins).then((value) => value.map((chat) => chat.username != null ? '@${chat.username}' : chat.firstName).toList());
    await teledart.sendMessage(
      chatId,
      'Current settings:\n'
      'Referral threshold: ${_config.referralThreshold}\n'
      'Channel: @${_config.channelUsername}\n'
      'Private group link: ${_config.privateGroupLink}\n'
      'Admins: ${adminNames.join(", ")}',
    );
  }

  Future<void> _requestSubscription(int chatId) async {
    await teledart.sendMessage(
      chatId,
      '❗️ Botdan foydalanish uchun kanalimizga a\'zo bo\'ling:',
      replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
        [InlineKeyboardButton(text: '📢 Kanalga o\'tish', url: 'https://t.me/${_config.channelUsername}')],
        [InlineKeyboardButton(text: '✅ Tekshirish', callbackData: 'check_subscription')]
      ]),
    );
  }

  Future<void> _handleStartCommand(Message message) async {
    if (message.from == null) return;

    final userId = message.from!.id.toString();
    final chatId = message.chat.id;
    String? referrerId;

    if (message.text != null && message.text!.contains('/start ')) {
      referrerId = message.text!.split('/start ')[1].trim();
    }

    try {
      final isSubscribed = await _checkSubscription(int.tryParse(userId)!) || _isAdmin(userId);

      if (!isSubscribed) {
        await _requestSubscription(chatId);
        return;
      }

      if (!_users.containsKey(userId)) {
        _users[userId] = User(userId);
        _saveDebouncer.run(_saveUsers);
      }

      if (referrerId != null && referrerId != userId) {
        await _addUser(userId, referrerId);
        await _sendWelcomeMessage(chatId, userId, true);
      } else {
        await _sendWelcomeMessage(chatId, userId, false);
      }
    } catch (e) {
      await teledart.sendMessage(chatId, 'Sorry, there was an error processing your request.');
      print('Error in start command: $e');
    }
  }

  Future<void> _handleCallbackQuery(CallbackQuery callbackQuery) async {
    if (callbackQuery.message == null) return;

    final userId = callbackQuery.from.id.toString();
    final chatId = callbackQuery.message!.chat.id;
    final messageId = callbackQuery.message!.messageId;

    if (callbackQuery.data == 'check_subscription') {
      final isSubscribed = await _checkSubscription(callbackQuery.from.id);

      if (isSubscribed) {
        await teledart.deleteMessage(chatId, messageId);
        if (_users.containsKey(userId)) {
          await _handleStatsCommand(callbackQuery.message!);
        } else {
          await _sendWelcomeMessage(chatId, userId, false);
        }
      } else {
        await teledart.answerCallbackQuery(
          callbackQuery.id,
          text: "❌ Siz hali kanalga a'zo bo'lmagansiz!",
          showAlert: true,
        );
      }
      return;
    }
    switch (callbackQuery.data) {
      case 'stats':
        final user = _users[userId];
        final statsMessage = "Taklif qilgan do'stlaringiz:\n"
            '👥 Barcha referallar: ${user?.referralCount ?? 0}\n'
            '🎯 Guruhga havolani olish uchun: ${user != null ? _config.referralThreshold - user.referralCount : _config.referralThreshold}';

        await teledart.editMessageText(statsMessage,
            chatId: callbackQuery.message!.chat.id,
            messageId: callbackQuery.message!.messageId,
            replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
              [InlineKeyboardButton(text: '🔄 Havolani ulashish', callbackData: 'share')]
            ]));
        break;

      case 'share':
        final referralLink = 'https://t.me/$username?start=$userId';
        final shareMessage = "Mohd&Lisa's IELTS marafoniga BEPUL qatnashish";
        final encodedMessage = Uri.encodeComponent(shareMessage);
        final shareUrl = 'https://t.me/share/url?url=${Uri.encodeComponent(referralLink)}&text=$encodedMessage';

        await teledart.editMessageText("Referal havolangizni ulashing:\n\n$referralLink",
            chatId: callbackQuery.message!.chat.id,
            messageId: callbackQuery.message!.messageId,
            replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
              [InlineKeyboardButton(text: "🔗 Do'stlarni taklif qilish", url: shareUrl)],
              [InlineKeyboardButton(text: "📊 Statistikani ko'rish", callbackData: 'stats')]
            ]));
        break;
    }

    await teledart.answerCallbackQuery(callbackQuery.id);
  }

  Future<void> _sendWelcomeMessage(int chatId, String userId, bool isReferred) async {
    final referralLink = 'https://t.me/$username?start=$userId';
    final shareMessage = "Mohd&Lisa's IELTS marafoniga BEPUL qatnashish";
    final encodedMessage = Uri.encodeComponent(shareMessage);
    final shareUrl = 'https://t.me/share/url?url=${Uri.encodeComponent(referralLink)}&text=$encodedMessage';

    final message =
        'Assalomu alaykum. Marafonimizga xush kelibsiz!\n\nMarafonga qo\'shilish uchun botga ${_config.referralThreshold} ta do\'stingizni taklif qiling.\n\nReferal havolangiz: $referralLink';

    await teledart.sendMessage(chatId, message,
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: "🔗 Do'stlarni taklif qilish", url: shareUrl)],
          [InlineKeyboardButton(text: "📊 Statistikani ko'rish", callbackData: 'stats')]
        ]));
  }

  Future<void> _addUser(String userId, String referrerId) async {
    try {
      print('Processing referral: userId=$userId, referrerId=$referrerId');

      final referrer = _users[referrerId];
      if (referrer != null) {
        print('Before increment: referralCount=${referrer.referralCount}');
        referrer.referralCount++;
        print('After increment: referralCount=${referrer.referralCount}');

        if (referrer.referralCount == _config.referralThreshold) {
          await _handleReferralThresholdReached(referrerId);
        }

        await _saveUsers();
        print('Users saved successfully');
      } else {
        print('Referrer not found in users list: $referrerId');
      }
    } catch (e, stackTrace) {
      print('Error in _addUser: $e\n$stackTrace');
    }
  }

  Future<void> _handleReferralThresholdReached(String referrerId) async {
    try {
      await teledart.sendMessage(
          int.parse(referrerId),
          "🎉 Tabriklaymiz! Siz ${_config.referralThreshold} ta do'stingizni taklif qildingiz!\n"
          "Havolani bosib marafonga qo'shilishingiz mumkin:",
          replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
            [
              InlineKeyboardButton(
                text: "🎯 Maxfiy guruhga qo'shilish",
                url: _config.privateGroupLink,
              )
            ]
          ]));
    } catch (e) {
      print('Error sending threshold notification: $e');
    }
  }

  Future<void> _handleStatsCommand(Message message) async {
    if (message.from == null) return;

    final userId = message.from!.id.toString();
    final user = _users[userId];

    await teledart.sendMessage(
        message.chat.id,
        '📊 Taklif qilgan do\'stlaringiz:\n'
        '👥 Barcha referallar: ${user?.referralCount ?? 0}\n'
        "🎯 Marafonga qo'shilish uchun: ${user != null ? _config.referralThreshold - user.referralCount : _config.referralThreshold}",
        replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
          [InlineKeyboardButton(text: '🔄 Havolani ulashish', callbackData: 'share')]
        ]));
  }

  Future<void> _handleMessage(Message message) async {
    if (message.text == null) return;

    try {
      await teledart.sendMessage(
          message.chat.id,
          'Quyidagi buyruqlardan foydalaning:\n'
          '/start - Taklif havolasini olish\n'
          '/stats - Natijani ko\'rish',
          replyMarkup: InlineKeyboardMarkup(inlineKeyboard: [
            [InlineKeyboardButton(text: '📊 Statistikani ko\'rish', callbackData: 'stats')]
          ]));
    } catch (e) {
      print('Error handling message: $e');
    }
  }
}
