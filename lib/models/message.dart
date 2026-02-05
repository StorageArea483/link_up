class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String text;
  final String? imageId;
  final String status;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.imageId,
    required this.status,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['\$id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderId: json['senderId'] ?? '',
      receiverId: json['receiverId'] ?? '',
      text: json['text'] ?? '',
      imageId: json['imageId'],
      status: json['status'] ?? 'sent',
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  bool isSentByMe(String currentUserId) {
    return senderId == currentUserId;
  }
}
