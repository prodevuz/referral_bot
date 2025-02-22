class Config {
  int referralThreshold;
  String channelUsername;
  String privateGroupLink;
  List<String> adminIds;

  Config({
    required this.referralThreshold,
    required this.channelUsername,
    required this.privateGroupLink,
    required this.adminIds,
  });

  Map<String, dynamic> toJson() => {
        'referralThreshold': referralThreshold,
        'channelUsername': channelUsername,
        'privateGroupLink': privateGroupLink,
        'adminIds': adminIds,
      };

  factory Config.fromJson(Map<String, dynamic> json) => Config(
        referralThreshold: json['referralThreshold'] as int,
        channelUsername: json['channelUsername'] as String,
        privateGroupLink: json['privateGroupLink'] as String,
        adminIds: List<String>.from(json['adminIds']),
      );

  factory Config.defaultConfig() => Config(
        referralThreshold: 3,
        channelUsername: 'mohdlisas',
        privateGroupLink: 'https://t.me/mohdlisas',
        adminIds: ['6650326836', '6559889263', '7669997303'],
      );
}
