import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _db;

  DatabaseHelper._internal();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'right_answer.db');
    return openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createCoreTablesV1(db);
    await _createQueueTable(db);
    await _createChatTables(db);
    await _createExamTables(db);
    // rawContent column is included in _createCoreTablesV1 for fresh installs
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createQueueTable(db);
    if (oldVersion < 3) await _createChatTables(db);
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE chapters ADD COLUMN rawContent TEXT NOT NULL DEFAULT ""',
      );
    }
    if (oldVersion < 5) await _createExamTables(db);
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE chat_messages ADD COLUMN responseLanguage TEXT',
      );
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE chat_messages ADD COLUMN sourceChunks TEXT',
      );
    }
  }

  Future<void> _createCoreTablesV1(Database db) async {
    await db.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        subjectId TEXT NOT NULL,
        title TEXT NOT NULL,
        className TEXT NOT NULL,
        rawContent TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL,
        FOREIGN KEY (subjectId) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE chunks (
        id TEXT PRIMARY KEY,
        chapterId TEXT NOT NULL,
        chunkIndex INTEGER NOT NULL,
        text TEXT NOT NULL,
        embeddingJson TEXT,
        page INTEGER,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE saved_outputs (
        id TEXT PRIMARY KEY,
        subjectId TEXT NOT NULL,
        chapterId TEXT NOT NULL,
        toolType TEXT NOT NULL,
        question TEXT,
        answer TEXT NOT NULL,
        language TEXT NOT NULL,
        usedChunkIds TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE usage_logs (
        id TEXT PRIMARY KEY,
        toolType TEXT NOT NULL,
        inputTokensEstimate INTEGER NOT NULL,
        outputTokensEstimate INTEGER NOT NULL,
        estimatedCost REAL NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS request_queue (
        id TEXT PRIMARY KEY,
        chapterId TEXT NOT NULL,
        subjectId TEXT NOT NULL,
        toolType TEXT NOT NULL,
        question TEXT,
        language TEXT NOT NULL,
        gradeLevel TEXT NOT NULL,
        tone TEXT NOT NULL,
        outputLength TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        errorMessage TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createChatTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chats (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        subjectId TEXT,
        subjectName TEXT,
        chapterIds TEXT NOT NULL DEFAULT '',
        chapterNames TEXT NOT NULL DEFAULT '',
        isTemporary INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        chatId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        imagePath TEXT,
        responseLanguage TEXT,
        responseLength TEXT NOT NULL DEFAULT 'normal',
        reasoningLevel TEXT NOT NULL DEFAULT 'mid',
        tokenCount INTEGER NOT NULL DEFAULT 0,
        cost REAL NOT NULL DEFAULT 0,
        sourceChunks TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (chatId) REFERENCES chats(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createExamTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exams (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        subjectId TEXT,
        subjectName TEXT,
        chapterIds TEXT NOT NULL DEFAULT '',
        chapterNames TEXT NOT NULL DEFAULT '',
        questionCount INTEGER NOT NULL DEFAULT 0,
        timeLimit INTEGER,
        difficulty TEXT NOT NULL DEFAULT 'medium',
        mcqOptionCount INTEGER NOT NULL DEFAULT 4,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_questions (
        id TEXT PRIMARY KEY,
        examId TEXT NOT NULL,
        questionIndex INTEGER NOT NULL,
        type TEXT NOT NULL,
        question TEXT NOT NULL,
        options TEXT,
        correctAnswer TEXT NOT NULL,
        explanation TEXT,
        userAnswer TEXT,
        FOREIGN KEY (examId) REFERENCES exams(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_messages (
        id TEXT PRIMARY KEY,
        examId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        imagePath TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (examId) REFERENCES exams(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('exam_messages');
    await db.delete('exam_questions');
    await db.delete('exams');
    await db.delete('chat_messages');
    await db.delete('chats');
    await db.delete('request_queue');
    await db.delete('chunks');
    await db.delete('saved_outputs');
    await db.delete('usage_logs');
    await db.delete('chapters');
    await db.delete('subjects');
  }
}
