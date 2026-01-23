class LogEntry {
  int? id;
  final int timestamp;
  final String logLevel;
  final String tag;
  final String message;
  String? source;
  int sent;
  int retryCount;
  final int createdAt;

  LogEntry({
    this.id,
    required this.timestamp,
    required this.logLevel,
    required this.tag,
    required this.message,
    this.source,
    this.sent = 0,
    this.retryCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'log_level': logLevel,
      'tag': tag,
      'message': message,
      'source': source,
      'sent': sent,
      'retry_count': retryCount,
      'created_at': createdAt,
    };
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: map['id'],
      timestamp: map['timestamp'],
      logLevel: map['log_level'],
      tag: map['tag'],
      message: map['message'],
      source: map['source'],
      sent: map['sent'],
      retryCount: map['retry_count'],
      createdAt: map['created_at'],
    );
  }

  @override
  String toString() {
    return 'LogEntry(id: $id, timestamp: $timestamp, level: $logLevel, tag: $tag, message: ${message.length > 50 ? '${message.substring(0, 50)}...' : message})';
  }
}