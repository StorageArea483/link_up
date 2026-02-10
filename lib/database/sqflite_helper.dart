import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:link_up/models/message.dart';

class SqfliteHelper {
  static Database? _database;
  static const String _databaseName = 'chat_database.db';
  static const int _databaseVersion = 1;

  // Table name
  static const String tableMessages = 'messages';

  // Column names
  static const String columnId = 'id';
  static const String columnChatId = 'chatId';
  static const String columnSenderId = 'senderId';
  static const String columnReceiverId = 'receiverId';
  static const String columnText = 'text';
  static const String columnImageId = 'imageId';
  static const String columnAudioId = 'audioId';
  static const String columnAudioPath = 'audioPath';
  static const String columnStatus = 'status';
  static const String columnCreatedAt = 'createdAt';

  /// Get database instance (singleton pattern)
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  /// Create the messages table
  /// Only stores delivered messages for offline viewing
  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableMessages (
        $columnId TEXT PRIMARY KEY,
        $columnChatId TEXT NOT NULL,
        $columnSenderId TEXT NOT NULL,
        $columnReceiverId TEXT NOT NULL,
        $columnText TEXT NOT NULL,
        $columnImageId TEXT,
        $columnAudioId TEXT,
        $columnAudioPath TEXT,
        $columnStatus TEXT NOT NULL,
        $columnCreatedAt TEXT NOT NULL
      )
    ''');
  }

  /// Insert a delivered message into SQLite database
  /// Only stores metadata - images will be loaded from Appwrite when online
  static Future<bool> insertDeliveredMessage(Message message) async {
    if (message.status != 'delivered') {
      return false;
    }

    final db = await database;

    try {
      await db.insert(tableMessages, {
        columnId: message.id,
        columnChatId: message.chatId,
        columnSenderId: message.senderId,
        columnReceiverId: message.receiverId,
        columnText: message.text,
        columnImageId: message.imageId,
        columnAudioId: message.audioId,
        columnAudioPath: message.audioPath,
        columnStatus: message.status,
        columnCreatedAt: message.createdAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Message>> getLastMessage(String chatId) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        tableMessages,
        where: '$columnChatId = ?',
        whereArgs: [chatId],
        orderBy: '$columnCreatedAt DESC',
        limit: 1,
      );

      if (maps.isEmpty) return [];

      return maps.map((map) {
        return Message(
          id: map[columnId],
          chatId: map[columnChatId],
          senderId: map[columnSenderId],
          receiverId: map[columnReceiverId],
          text: map[columnText],
          imageId: map[columnImageId],
          audioId: map[columnAudioId],
          audioPath: map[columnAudioPath],
          status: map[columnStatus],
          createdAt: DateTime.parse(map[columnCreatedAt]),
        );
      }).toList();
    } catch (e) {
      // Return empty list on error, don't throw
      return [];
    }
  }

  static Future<List<Message>> getDeliveredMessages(String chatId) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        tableMessages,
        where: '$columnChatId = ?',
        whereArgs: [chatId],
        orderBy: '$columnCreatedAt DESC',
      );

      if (maps.isEmpty) return [];

      return maps.map((map) {
        return Message(
          id: map[columnId],
          chatId: map[columnChatId],
          senderId: map[columnSenderId],
          receiverId: map[columnReceiverId],
          text: map[columnText],
          imageId: map[columnImageId],
          audioId: map[columnAudioId],
          audioPath: map[columnAudioPath],
          status: map[columnStatus],
          createdAt: DateTime.parse(map[columnCreatedAt]),
        );
      }).toList();
    } catch (e) {
      // Return empty list on error, don't throw
      return [];
    }
  }

  /// Get all messages for a chat (both delivered and any other status)
  /// This is a backup method to ensure we never lose messages
  static Future<List<Message>> getAllMessagesForChat(String chatId) async {
    return await getDeliveredMessages(chatId);
  }

  /// Check if a message already exists in Sqflite
  static Future<bool> messageExists(String messageId) async {
    final db = await database;

    try {
      final result = await db.query(
        tableMessages,
        where: '$columnId = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Clear all messages for a specific chat (optional utility)
  static Future<void> clearChatMessages(String chatId) async {
    final db = await database;

    try {
      await db.delete(
        tableMessages,
        where: '$columnChatId = ?',
        whereArgs: [chatId],
      );
    } catch (e) {
      // Silent failure
    }
  }

  /// Close the database connection
  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
