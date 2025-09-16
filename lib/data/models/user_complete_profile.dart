class UserCompleteProfile {
  final int userId;
  final String account;
  final String password;
  final String? avatarUrl;
  final String username;
  final String? company;
  final String? jobTitle;
  final String? skill;
  final String? email;
  final String? phone;
  final String? qrCodeUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<SocialLink> socialLinks;

  UserCompleteProfile({
    required this.userId,
    required this.account,
    required this.password,
    this.avatarUrl,
    required this.username,
    this.company,
    this.jobTitle,
    this.skill,
    this.email,
    this.phone,
    this.qrCodeUrl,
    required this.createdAt,
    this.updatedAt,
    required this.socialLinks,
  });

  factory UserCompleteProfile.fromJson(Map<String, dynamic> json) {
    return UserCompleteProfile(
      userId: json['user_id'],
      account: json['account'],
      password: json['password'],
      avatarUrl: json['avatar_url'],
      username: json['username'],
      company: json['company'],
      jobTitle: json['job_title'],
      skill: json['skill'],
      email: json['email'],
      phone: json['phone'],
      qrCodeUrl: json['qr_code_url'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      socialLinks: (json['social_links'] as List<dynamic>)
          .map((e) => SocialLink.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'account': account,
      'password': password,
      'avatar_url': avatarUrl,
      'username': username,
      'company': company,
      'job_title': jobTitle,
      'skill': skill,
      'email': email,
      'phone': phone,
      'qr_code_url': qrCodeUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'social_links': socialLinks.map((e) => e.toJson()).toList(),
    };
  }
}

class SocialLink {
  final int linkId;
  final String platform;
  final String url;
  final String? displayName;
  final int displayOrder;
  final bool isActive;

  SocialLink({
    required this.linkId,
    required this.platform,
    required this.url,
    this.displayName,
    required this.displayOrder,
    required this.isActive,
  });

  factory SocialLink.fromJson(Map<String, dynamic> json) {
    return SocialLink(
      linkId: json['link_id'],
      platform: json['platform'],
      url: json['url'],
      displayName: json['display_name'],
      displayOrder: json['display_order'],
      isActive: json['is_active'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'link_id': linkId,
      'platform': platform,
      'url': url,
      'display_name': displayName,
      'display_order': displayOrder,
      'is_active': isActive,
    };
  }
}

// copyWith
extension UserCompleteProfileCopy on UserCompleteProfile {
  UserCompleteProfile copyWith({
    String? avatarUrl,
    String? username,
    String? company,
    String? jobTitle,
    String? skill,
    String? email,
    String? phone,
    String? qrCodeUrl,
    List<SocialLink>? socialLinks,
  }) {
    return UserCompleteProfile(
      userId: userId,
      account: account,
      password: password,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      username: username ?? this.username,
      company: company ?? this.company,
      jobTitle: jobTitle ?? this.jobTitle,
      skill: skill ?? this.skill,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      socialLinks: socialLinks ?? this.socialLinks,
    );
  }
}
