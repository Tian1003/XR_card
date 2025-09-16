class ContactRelationship {
  final int contactId;
  final int requesterId;
  final int friendId;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // requester 資訊
  final String requesterUsername;
  final String? requesterCompany;
  final String? requesterJobTitle;
  final String? requesterAvatar;

  // friend 資訊
  final String friendUsername;
  final String? friendCompany;
  final String? friendJobTitle;
  final String? friendAvatar;

  // 雙方各自設定
  final String? requesterSetNickname;
  final String? requesterSetNote;
  final List<String>? requesterSetTags;

  final String? friendSetNickname;
  final String? friendSetNote;
  final List<String>? friendSetTags;

  ContactRelationship({
    required this.contactId,
    required this.requesterId,
    required this.friendId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    required this.requesterUsername,
    this.requesterCompany,
    this.requesterJobTitle,
    this.requesterAvatar,
    required this.friendUsername,
    this.friendCompany,
    this.friendJobTitle,
    this.friendAvatar,
    this.requesterSetNickname,
    this.requesterSetNote,
    this.requesterSetTags,
    this.friendSetNickname,
    this.friendSetNote,
    this.friendSetTags,
  });

  // 私有工具方法：解析 tags 字段 (JSON to List)
  static List<String>? _parseTags(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }

  factory ContactRelationship.fromJson(Map<String, dynamic> json) {
    return ContactRelationship(
      contactId: json['contact_id'],
      requesterId: json['requester_id'],
      friendId: json['friend_id'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      requesterUsername: json['requester_username'],
      requesterCompany: json['requester_company'],
      requesterJobTitle: json['requester_job_title'],
      requesterAvatar: json['requester_avatar'],
      friendUsername: json['friend_username'],
      friendCompany: json['friend_company'],
      friendJobTitle: json['friend_job_title'],
      friendAvatar: json['friend_avatar'],
      requesterSetNickname: json['requester_set_nickname'],
      requesterSetNote: json['requester_set_note'],
      requesterSetTags: _parseTags(json['requester_set_tags']),
      friendSetNickname: json['friend_set_nickname'],
      friendSetNote: json['friend_set_note'],
      friendSetTags: _parseTags(json['friend_set_tags']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contact_id': contactId,
      'requester_id': requesterId,
      'friend_id': friendId,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'requester_username': requesterUsername,
      'requester_company': requesterCompany,
      'requester_job_title': requesterJobTitle,
      'requester_avatar': requesterAvatar,
      'friend_username': friendUsername,
      'friend_company': friendCompany,
      'friend_job_title': friendJobTitle,
      'friend_avatar': friendAvatar,
      'requester_set_nickname': requesterSetNickname,
      'requester_set_note': requesterSetNote,
      'requester_set_tags': requesterSetTags,
      'friend_set_nickname': friendSetNickname,
      'friend_set_note': friendSetNote,
      'friend_set_tags': friendSetTags,
    };
  }
}
