import 'dart:developer';
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
  static const String columnStatus = 'status';
  static const String columnCreatedAt = 'createdAt';

  /// Get database instance (singleton pattern)
  static Future<Database> get database async {
    try {
      if (_database != null) return _database!;
      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      log('Database initialization failed: $e', name: 'SqfliteHelper');
      rethrow;
    }
  }

  /// Initialize the database
  static Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _databaseName);

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
      );
    } catch (e) {
      log('Database setup failed: $e', name: 'SqfliteHelper');
      rethrow;
    }
  }

  /// Create the messages table
  /// Only stores delivered messages for offline viewing
  static Future<void> _onCreate(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $tableMessages (
          $columnId TEXT PRIMARY KEY,
          $columnChatId TEXT NOT NULL,
          $columnSenderId TEXT NOT NULL,
          $columnReceiverId TEXT NOT NULL,
          $columnText TEXT NOT NULL,
          $columnImageId TEXT,
          $columnAudioId TEXT,
          $columnStatus TEXT NOT NULL,
          $columnCreatedAt TEXT NOT NULL
        )
      ''');
    } catch (e) {
      log('Database table creation failed: $e', name: 'SqfliteHelper');
      rethrow;
    }
  }

  /// Insert or update a message in SQLite database
  static Future<bool> insertMessage(Message message) async {
    try {
      final db = await database;
      await db.insert(tableMessages, {
        columnId: message.id,
        columnChatId: message.chatId,
        columnSenderId: message.senderId,
        columnReceiverId: message.receiverId,
        columnText: message.text,
        columnImageId: message.imageId,
        columnAudioId: message.audioId,
        columnStatus: message.status,
        columnCreatedAt: message.createdAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return true;
    } catch (e) {
      // Return false on insert failure - caller can handle appropriately
      return false;
    }
  }

  static Future<List<Message>> getLastMessage(String chatId) async {
    try {
      final db = await database;
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
          status: map[columnStatus],
          createdAt: DateTime.parse(map[columnCreatedAt]),
        );
      }).toList();
    } catch (e) {
      // Return empty list on query failure
      return [];
    }
  }

  static Future<List<Message>> getDeliveredMessages(String chatId) async {
    try {
      final db = await database;
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
          status: map[columnStatus],
          createdAt: DateTime.parse(map[columnCreatedAt]),
        );
      }).toList();
    } catch (e) {
      // Return empty list on query failure
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
    try {
      final db = await database;
      final result = await db.query(
        tableMessages,
        where: '$columnId = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      // Return false on query failure
      return false;
    }
  }

  /// Clear all messages for a specific chat (optional utility)
  static Future<void> clearChatMessages(String chatId) async {
    try {
      final db = await database;
      await db.delete(
        tableMessages,
        where: '$columnChatId = ?',
        whereArgs: [chatId],
      );
    } catch (e) {
      // Silent failure for cleanup operations
    }
  }

  /// Close the database connection
  static Future<void> close() async {
    try {
      final db = await database;
      await db.close();
      _database = null;
    } catch (e) {
      // Silent failure for cleanup operations
    }
  }
}
