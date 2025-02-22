class User {
  final String id;
  String? referrerId;
  int referralCount;

  User(this.id, {this.referrerId, this.referralCount = 0});

  Map<String, dynamic> toJson() => {
        'id': id,
        'referrerId': referrerId,
        'referralCount': referralCount,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        json['id'] as String,
        referrerId: json['referrerId'] as String?,
        referralCount: json['referralCount'] as int,
      );
}
