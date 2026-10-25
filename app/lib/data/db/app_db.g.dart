// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $ChatsTable extends Chats with TableInfo<$ChatsTable, Chat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('New chat'),
  );
  static const VerificationMeta _modelRefMeta = const VerificationMeta(
    'modelRef',
  );
  @override
  late final GeneratedColumn<String> modelRef = GeneratedColumn<String>(
    'model_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _systemPromptMeta = const VerificationMeta(
    'systemPrompt',
  );
  @override
  late final GeneratedColumn<String> systemPrompt = GeneratedColumn<String>(
    'system_prompt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _settingsJsonMeta = const VerificationMeta(
    'settingsJson',
  );
  @override
  late final GeneratedColumn<String> settingsJson = GeneratedColumn<String>(
    'settings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _activeLeafIdMeta = const VerificationMeta(
    'activeLeafId',
  );
  @override
  late final GeneratedColumn<String> activeLeafId = GeneratedColumn<String>(
    'active_leaf_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderMeta = const VerificationMeta('folder');
  @override
  late final GeneratedColumn<String> folder = GeneratedColumn<String>(
    'folder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    modelRef,
    systemPrompt,
    settingsJson,
    activeLeafId,
    folder,
    pinned,
    archived,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chats';
  @override
  VerificationContext validateIntegrity(
    Insertable<Chat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('model_ref')) {
      context.handle(
        _modelRefMeta,
        modelRef.isAcceptableOrUnknown(data['model_ref']!, _modelRefMeta),
      );
    }
    if (data.containsKey('system_prompt')) {
      context.handle(
        _systemPromptMeta,
        systemPrompt.isAcceptableOrUnknown(
          data['system_prompt']!,
          _systemPromptMeta,
        ),
      );
    }
    if (data.containsKey('settings_json')) {
      context.handle(
        _settingsJsonMeta,
        settingsJson.isAcceptableOrUnknown(
          data['settings_json']!,
          _settingsJsonMeta,
        ),
      );
    }
    if (data.containsKey('active_leaf_id')) {
      context.handle(
        _activeLeafIdMeta,
        activeLeafId.isAcceptableOrUnknown(
          data['active_leaf_id']!,
          _activeLeafIdMeta,
        ),
      );
    }
    if (data.containsKey('folder')) {
      context.handle(
        _folderMeta,
        folder.isAcceptableOrUnknown(data['folder']!, _folderMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chat(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      modelRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_ref'],
      ),
      systemPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_prompt'],
      ),
      settingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings_json'],
      )!,
      activeLeafId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_leaf_id'],
      ),
      folder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder'],
      ),
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ChatsTable createAlias(String alias) {
    return $ChatsTable(attachedDatabase, alias);
  }
}

class Chat extends DataClass implements Insertable<Chat> {
  final String id;
  final String title;
  final String? modelRef;
  final String? systemPrompt;
  final String settingsJson;
  final String? activeLeafId;
  final String? folder;
  final bool pinned;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Chat({
    required this.id,
    required this.title,
    this.modelRef,
    this.systemPrompt,
    required this.settingsJson,
    this.activeLeafId,
    this.folder,
    required this.pinned,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || modelRef != null) {
      map['model_ref'] = Variable<String>(modelRef);
    }
    if (!nullToAbsent || systemPrompt != null) {
      map['system_prompt'] = Variable<String>(systemPrompt);
    }
    map['settings_json'] = Variable<String>(settingsJson);
    if (!nullToAbsent || activeLeafId != null) {
      map['active_leaf_id'] = Variable<String>(activeLeafId);
    }
    if (!nullToAbsent || folder != null) {
      map['folder'] = Variable<String>(folder);
    }
    map['pinned'] = Variable<bool>(pinned);
    map['archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ChatsCompanion toCompanion(bool nullToAbsent) {
    return ChatsCompanion(
      id: Value(id),
      title: Value(title),
      modelRef: modelRef == null && nullToAbsent
          ? const Value.absent()
          : Value(modelRef),
      systemPrompt: systemPrompt == null && nullToAbsent
          ? const Value.absent()
          : Value(systemPrompt),
      settingsJson: Value(settingsJson),
      activeLeafId: activeLeafId == null && nullToAbsent
          ? const Value.absent()
          : Value(activeLeafId),
      folder: folder == null && nullToAbsent
          ? const Value.absent()
          : Value(folder),
      pinned: Value(pinned),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Chat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chat(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      modelRef: serializer.fromJson<String?>(json['modelRef']),
      systemPrompt: serializer.fromJson<String?>(json['systemPrompt']),
      settingsJson: serializer.fromJson<String>(json['settingsJson']),
      activeLeafId: serializer.fromJson<String?>(json['activeLeafId']),
      folder: serializer.fromJson<String?>(json['folder']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'modelRef': serializer.toJson<String?>(modelRef),
      'systemPrompt': serializer.toJson<String?>(systemPrompt),
      'settingsJson': serializer.toJson<String>(settingsJson),
      'activeLeafId': serializer.toJson<String?>(activeLeafId),
      'folder': serializer.toJson<String?>(folder),
      'pinned': serializer.toJson<bool>(pinned),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Chat copyWith({
    String? id,
    String? title,
    Value<String?> modelRef = const Value.absent(),
    Value<String?> systemPrompt = const Value.absent(),
    String? settingsJson,
    Value<String?> activeLeafId = const Value.absent(),
    Value<String?> folder = const Value.absent(),
    bool? pinned,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Chat(
    id: id ?? this.id,
    title: title ?? this.title,
    modelRef: modelRef.present ? modelRef.value : this.modelRef,
    systemPrompt: systemPrompt.present ? systemPrompt.value : this.systemPrompt,
    settingsJson: settingsJson ?? this.settingsJson,
    activeLeafId: activeLeafId.present ? activeLeafId.value : this.activeLeafId,
    folder: folder.present ? folder.value : this.folder,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Chat copyWithCompanion(ChatsCompanion data) {
    return Chat(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      modelRef: data.modelRef.present ? data.modelRef.value : this.modelRef,
      systemPrompt: data.systemPrompt.present
          ? data.systemPrompt.value
          : this.systemPrompt,
      settingsJson: data.settingsJson.present
          ? data.settingsJson.value
          : this.settingsJson,
      activeLeafId: data.activeLeafId.present
          ? data.activeLeafId.value
          : this.activeLeafId,
      folder: data.folder.present ? data.folder.value : this.folder,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chat(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('modelRef: $modelRef, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('activeLeafId: $activeLeafId, ')
          ..write('folder: $folder, ')
          ..write('pinned: $pinned, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    modelRef,
    systemPrompt,
    settingsJson,
    activeLeafId,
    folder,
    pinned,
    archived,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chat &&
          other.id == this.id &&
          other.title == this.title &&
          other.modelRef == this.modelRef &&
          other.systemPrompt == this.systemPrompt &&
          other.settingsJson == this.settingsJson &&
          other.activeLeafId == this.activeLeafId &&
          other.folder == this.folder &&
          other.pinned == this.pinned &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ChatsCompanion extends UpdateCompanion<Chat> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> modelRef;
  final Value<String?> systemPrompt;
  final Value<String> settingsJson;
  final Value<String?> activeLeafId;
  final Value<String?> folder;
  final Value<bool> pinned;
  final Value<bool> archived;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ChatsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.modelRef = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.settingsJson = const Value.absent(),
    this.activeLeafId = const Value.absent(),
    this.folder = const Value.absent(),
    this.pinned = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.modelRef = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.settingsJson = const Value.absent(),
    this.activeLeafId = const Value.absent(),
    this.folder = const Value.absent(),
    this.pinned = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Chat> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? modelRef,
    Expression<String>? systemPrompt,
    Expression<String>? settingsJson,
    Expression<String>? activeLeafId,
    Expression<String>? folder,
    Expression<bool>? pinned,
    Expression<bool>? archived,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (modelRef != null) 'model_ref': modelRef,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (settingsJson != null) 'settings_json': settingsJson,
      if (activeLeafId != null) 'active_leaf_id': activeLeafId,
      if (folder != null) 'folder': folder,
      if (pinned != null) 'pinned': pinned,
      if (archived != null) 'archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? modelRef,
    Value<String?>? systemPrompt,
    Value<String>? settingsJson,
    Value<String?>? activeLeafId,
    Value<String?>? folder,
    Value<bool>? pinned,
    Value<bool>? archived,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ChatsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      modelRef: modelRef ?? this.modelRef,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      settingsJson: settingsJson ?? this.settingsJson,
      activeLeafId: activeLeafId ?? this.activeLeafId,
      folder: folder ?? this.folder,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (modelRef.present) {
      map['model_ref'] = Variable<String>(modelRef.value);
    }
    if (systemPrompt.present) {
      map['system_prompt'] = Variable<String>(systemPrompt.value);
    }
    if (settingsJson.present) {
      map['settings_json'] = Variable<String>(settingsJson.value);
    }
    if (activeLeafId.present) {
      map['active_leaf_id'] = Variable<String>(activeLeafId.value);
    }
    if (folder.present) {
      map['folder'] = Variable<String>(folder.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('modelRef: $modelRef, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('activeLeafId: $activeLeafId, ')
          ..write('folder: $folder, ')
          ..write('pinned: $pinned, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chats (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('message'),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _reasoningMeta = const VerificationMeta(
    'reasoning',
  );
  @override
  late final GeneratedColumn<String> reasoning = GeneratedColumn<String>(
    'reasoning',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasoningMsMeta = const VerificationMeta(
    'reasoningMs',
  );
  @override
  late final GeneratedColumn<int> reasoningMs = GeneratedColumn<int>(
    'reasoning_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolCallsJsonMeta = const VerificationMeta(
    'toolCallsJson',
  );
  @override
  late final GeneratedColumn<String> toolCallsJson = GeneratedColumn<String>(
    'tool_calls_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolCallIdMeta = const VerificationMeta(
    'toolCallId',
  );
  @override
  late final GeneratedColumn<String> toolCallId = GeneratedColumn<String>(
    'tool_call_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolNameMeta = const VerificationMeta(
    'toolName',
  );
  @override
  late final GeneratedColumn<String> toolName = GeneratedColumn<String>(
    'tool_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolResultJsonMeta = const VerificationMeta(
    'toolResultJson',
  );
  @override
  late final GeneratedColumn<String> toolResultJson = GeneratedColumn<String>(
    'tool_result_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelRefMeta = const VerificationMeta(
    'modelRef',
  );
  @override
  late final GeneratedColumn<String> modelRef = GeneratedColumn<String>(
    'model_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('done'),
  );
  static const VerificationMeta _errorTextMeta = const VerificationMeta(
    'errorText',
  );
  @override
  late final GeneratedColumn<String> errorText = GeneratedColumn<String>(
    'error_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _promptTokensMeta = const VerificationMeta(
    'promptTokens',
  );
  @override
  late final GeneratedColumn<int> promptTokens = GeneratedColumn<int>(
    'prompt_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completionTokensMeta = const VerificationMeta(
    'completionTokens',
  );
  @override
  late final GeneratedColumn<int> completionTokens = GeneratedColumn<int>(
    'completion_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokensPerSecondMeta = const VerificationMeta(
    'tokensPerSecond',
  );
  @override
  late final GeneratedColumn<double> tokensPerSecond = GeneratedColumn<double>(
    'tokens_per_second',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    chatId,
    parentId,
    role,
    kind,
    content,
    reasoning,
    reasoningMs,
    toolCallsJson,
    toolCallId,
    toolName,
    toolResultJson,
    attachmentsJson,
    audioPath,
    modelRef,
    status,
    errorText,
    promptTokens,
    completionTokens,
    tokensPerSecond,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('reasoning')) {
      context.handle(
        _reasoningMeta,
        reasoning.isAcceptableOrUnknown(data['reasoning']!, _reasoningMeta),
      );
    }
    if (data.containsKey('reasoning_ms')) {
      context.handle(
        _reasoningMsMeta,
        reasoningMs.isAcceptableOrUnknown(
          data['reasoning_ms']!,
          _reasoningMsMeta,
        ),
      );
    }
    if (data.containsKey('tool_calls_json')) {
      context.handle(
        _toolCallsJsonMeta,
        toolCallsJson.isAcceptableOrUnknown(
          data['tool_calls_json']!,
          _toolCallsJsonMeta,
        ),
      );
    }
    if (data.containsKey('tool_call_id')) {
      context.handle(
        _toolCallIdMeta,
        toolCallId.isAcceptableOrUnknown(
          data['tool_call_id']!,
          _toolCallIdMeta,
        ),
      );
    }
    if (data.containsKey('tool_name')) {
      context.handle(
        _toolNameMeta,
        toolName.isAcceptableOrUnknown(data['tool_name']!, _toolNameMeta),
      );
    }
    if (data.containsKey('tool_result_json')) {
      context.handle(
        _toolResultJsonMeta,
        toolResultJson.isAcceptableOrUnknown(
          data['tool_result_json']!,
          _toolResultJsonMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    if (data.containsKey('model_ref')) {
      context.handle(
        _modelRefMeta,
        modelRef.isAcceptableOrUnknown(data['model_ref']!, _modelRefMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error_text')) {
      context.handle(
        _errorTextMeta,
        errorText.isAcceptableOrUnknown(data['error_text']!, _errorTextMeta),
      );
    }
    if (data.containsKey('prompt_tokens')) {
      context.handle(
        _promptTokensMeta,
        promptTokens.isAcceptableOrUnknown(
          data['prompt_tokens']!,
          _promptTokensMeta,
        ),
      );
    }
    if (data.containsKey('completion_tokens')) {
      context.handle(
        _completionTokensMeta,
        completionTokens.isAcceptableOrUnknown(
          data['completion_tokens']!,
          _completionTokensMeta,
        ),
      );
    }
    if (data.containsKey('tokens_per_second')) {
      context.handle(
        _tokensPerSecondMeta,
        tokensPerSecond.isAcceptableOrUnknown(
          data['tokens_per_second']!,
          _tokensPerSecondMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      reasoning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning'],
      ),
      reasoningMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reasoning_ms'],
      ),
      toolCallsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_calls_json'],
      ),
      toolCallId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_call_id'],
      ),
      toolName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_name'],
      ),
      toolResultJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_result_json'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      ),
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
      modelRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_ref'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      errorText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_text'],
      ),
      promptTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}prompt_tokens'],
      ),
      completionTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completion_tokens'],
      ),
      tokensPerSecond: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tokens_per_second'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String chatId;
  final String? parentId;
  final String role;
  final String kind;
  final String content;
  final String? reasoning;
  final int? reasoningMs;
  final String? toolCallsJson;
  final String? toolCallId;
  final String? toolName;
  final String? toolResultJson;
  final String? attachmentsJson;
  final String? audioPath;
  final String? modelRef;
  final String status;
  final String? errorText;
  final int? promptTokens;
  final int? completionTokens;
  final double? tokensPerSecond;
  final DateTime createdAt;
  const Message({
    required this.id,
    required this.chatId,
    this.parentId,
    required this.role,
    required this.kind,
    required this.content,
    this.reasoning,
    this.reasoningMs,
    this.toolCallsJson,
    this.toolCallId,
    this.toolName,
    this.toolResultJson,
    this.attachmentsJson,
    this.audioPath,
    this.modelRef,
    required this.status,
    this.errorText,
    this.promptTokens,
    this.completionTokens,
    this.tokensPerSecond,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['chat_id'] = Variable<String>(chatId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['role'] = Variable<String>(role);
    map['kind'] = Variable<String>(kind);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || reasoning != null) {
      map['reasoning'] = Variable<String>(reasoning);
    }
    if (!nullToAbsent || reasoningMs != null) {
      map['reasoning_ms'] = Variable<int>(reasoningMs);
    }
    if (!nullToAbsent || toolCallsJson != null) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson);
    }
    if (!nullToAbsent || toolCallId != null) {
      map['tool_call_id'] = Variable<String>(toolCallId);
    }
    if (!nullToAbsent || toolName != null) {
      map['tool_name'] = Variable<String>(toolName);
    }
    if (!nullToAbsent || toolResultJson != null) {
      map['tool_result_json'] = Variable<String>(toolResultJson);
    }
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    if (!nullToAbsent || modelRef != null) {
      map['model_ref'] = Variable<String>(modelRef);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || errorText != null) {
      map['error_text'] = Variable<String>(errorText);
    }
    if (!nullToAbsent || promptTokens != null) {
      map['prompt_tokens'] = Variable<int>(promptTokens);
    }
    if (!nullToAbsent || completionTokens != null) {
      map['completion_tokens'] = Variable<int>(completionTokens);
    }
    if (!nullToAbsent || tokensPerSecond != null) {
      map['tokens_per_second'] = Variable<double>(tokensPerSecond);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      chatId: Value(chatId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      role: Value(role),
      kind: Value(kind),
      content: Value(content),
      reasoning: reasoning == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoning),
      reasoningMs: reasoningMs == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningMs),
      toolCallsJson: toolCallsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallsJson),
      toolCallId: toolCallId == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallId),
      toolName: toolName == null && nullToAbsent
          ? const Value.absent()
          : Value(toolName),
      toolResultJson: toolResultJson == null && nullToAbsent
          ? const Value.absent()
          : Value(toolResultJson),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      modelRef: modelRef == null && nullToAbsent
          ? const Value.absent()
          : Value(modelRef),
      status: Value(status),
      errorText: errorText == null && nullToAbsent
          ? const Value.absent()
          : Value(errorText),
      promptTokens: promptTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(promptTokens),
      completionTokens: completionTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(completionTokens),
      tokensPerSecond: tokensPerSecond == null && nullToAbsent
          ? const Value.absent()
          : Value(tokensPerSecond),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      chatId: serializer.fromJson<String>(json['chatId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      role: serializer.fromJson<String>(json['role']),
      kind: serializer.fromJson<String>(json['kind']),
      content: serializer.fromJson<String>(json['content']),
      reasoning: serializer.fromJson<String?>(json['reasoning']),
      reasoningMs: serializer.fromJson<int?>(json['reasoningMs']),
      toolCallsJson: serializer.fromJson<String?>(json['toolCallsJson']),
      toolCallId: serializer.fromJson<String?>(json['toolCallId']),
      toolName: serializer.fromJson<String?>(json['toolName']),
      toolResultJson: serializer.fromJson<String?>(json['toolResultJson']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      modelRef: serializer.fromJson<String?>(json['modelRef']),
      status: serializer.fromJson<String>(json['status']),
      errorText: serializer.fromJson<String?>(json['errorText']),
      promptTokens: serializer.fromJson<int?>(json['promptTokens']),
      completionTokens: serializer.fromJson<int?>(json['completionTokens']),
      tokensPerSecond: serializer.fromJson<double?>(json['tokensPerSecond']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'chatId': serializer.toJson<String>(chatId),
      'parentId': serializer.toJson<String?>(parentId),
      'role': serializer.toJson<String>(role),
      'kind': serializer.toJson<String>(kind),
      'content': serializer.toJson<String>(content),
      'reasoning': serializer.toJson<String?>(reasoning),
      'reasoningMs': serializer.toJson<int?>(reasoningMs),
      'toolCallsJson': serializer.toJson<String?>(toolCallsJson),
      'toolCallId': serializer.toJson<String?>(toolCallId),
      'toolName': serializer.toJson<String?>(toolName),
      'toolResultJson': serializer.toJson<String?>(toolResultJson),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
      'audioPath': serializer.toJson<String?>(audioPath),
      'modelRef': serializer.toJson<String?>(modelRef),
      'status': serializer.toJson<String>(status),
      'errorText': serializer.toJson<String?>(errorText),
      'promptTokens': serializer.toJson<int?>(promptTokens),
      'completionTokens': serializer.toJson<int?>(completionTokens),
      'tokensPerSecond': serializer.toJson<double?>(tokensPerSecond),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith({
    String? id,
    String? chatId,
    Value<String?> parentId = const Value.absent(),
    String? role,
    String? kind,
    String? content,
    Value<String?> reasoning = const Value.absent(),
    Value<int?> reasoningMs = const Value.absent(),
    Value<String?> toolCallsJson = const Value.absent(),
    Value<String?> toolCallId = const Value.absent(),
    Value<String?> toolName = const Value.absent(),
    Value<String?> toolResultJson = const Value.absent(),
    Value<String?> attachmentsJson = const Value.absent(),
    Value<String?> audioPath = const Value.absent(),
    Value<String?> modelRef = const Value.absent(),
    String? status,
    Value<String?> errorText = const Value.absent(),
    Value<int?> promptTokens = const Value.absent(),
    Value<int?> completionTokens = const Value.absent(),
    Value<double?> tokensPerSecond = const Value.absent(),
    DateTime? createdAt,
  }) => Message(
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    parentId: parentId.present ? parentId.value : this.parentId,
    role: role ?? this.role,
    kind: kind ?? this.kind,
    content: content ?? this.content,
    reasoning: reasoning.present ? reasoning.value : this.reasoning,
    reasoningMs: reasoningMs.present ? reasoningMs.value : this.reasoningMs,
    toolCallsJson: toolCallsJson.present
        ? toolCallsJson.value
        : this.toolCallsJson,
    toolCallId: toolCallId.present ? toolCallId.value : this.toolCallId,
    toolName: toolName.present ? toolName.value : this.toolName,
    toolResultJson: toolResultJson.present
        ? toolResultJson.value
        : this.toolResultJson,
    attachmentsJson: attachmentsJson.present
        ? attachmentsJson.value
        : this.attachmentsJson,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
    modelRef: modelRef.present ? modelRef.value : this.modelRef,
    status: status ?? this.status,
    errorText: errorText.present ? errorText.value : this.errorText,
    promptTokens: promptTokens.present ? promptTokens.value : this.promptTokens,
    completionTokens: completionTokens.present
        ? completionTokens.value
        : this.completionTokens,
    tokensPerSecond: tokensPerSecond.present
        ? tokensPerSecond.value
        : this.tokensPerSecond,
    createdAt: createdAt ?? this.createdAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      role: data.role.present ? data.role.value : this.role,
      kind: data.kind.present ? data.kind.value : this.kind,
      content: data.content.present ? data.content.value : this.content,
      reasoning: data.reasoning.present ? data.reasoning.value : this.reasoning,
      reasoningMs: data.reasoningMs.present
          ? data.reasoningMs.value
          : this.reasoningMs,
      toolCallsJson: data.toolCallsJson.present
          ? data.toolCallsJson.value
          : this.toolCallsJson,
      toolCallId: data.toolCallId.present
          ? data.toolCallId.value
          : this.toolCallId,
      toolName: data.toolName.present ? data.toolName.value : this.toolName,
      toolResultJson: data.toolResultJson.present
          ? data.toolResultJson.value
          : this.toolResultJson,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      modelRef: data.modelRef.present ? data.modelRef.value : this.modelRef,
      status: data.status.present ? data.status.value : this.status,
      errorText: data.errorText.present ? data.errorText.value : this.errorText,
      promptTokens: data.promptTokens.present
          ? data.promptTokens.value
          : this.promptTokens,
      completionTokens: data.completionTokens.present
          ? data.completionTokens.value
          : this.completionTokens,
      tokensPerSecond: data.tokensPerSecond.present
          ? data.tokensPerSecond.value
          : this.tokensPerSecond,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('parentId: $parentId, ')
          ..write('role: $role, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('reasoning: $reasoning, ')
          ..write('reasoningMs: $reasoningMs, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('toolResultJson: $toolResultJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('audioPath: $audioPath, ')
          ..write('modelRef: $modelRef, ')
          ..write('status: $status, ')
          ..write('errorText: $errorText, ')
          ..write('promptTokens: $promptTokens, ')
          ..write('completionTokens: $completionTokens, ')
          ..write('tokensPerSecond: $tokensPerSecond, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    chatId,
    parentId,
    role,
    kind,
    content,
    reasoning,
    reasoningMs,
    toolCallsJson,
    toolCallId,
    toolName,
    toolResultJson,
    attachmentsJson,
    audioPath,
    modelRef,
    status,
    errorText,
    promptTokens,
    completionTokens,
    tokensPerSecond,
    createdAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.chatId == this.chatId &&
          other.parentId == this.parentId &&
          other.role == this.role &&
          other.kind == this.kind &&
          other.content == this.content &&
          other.reasoning == this.reasoning &&
          other.reasoningMs == this.reasoningMs &&
          other.toolCallsJson == this.toolCallsJson &&
          other.toolCallId == this.toolCallId &&
          other.toolName == this.toolName &&
          other.toolResultJson == this.toolResultJson &&
          other.attachmentsJson == this.attachmentsJson &&
          other.audioPath == this.audioPath &&
          other.modelRef == this.modelRef &&
          other.status == this.status &&
          other.errorText == this.errorText &&
          other.promptTokens == this.promptTokens &&
          other.completionTokens == this.completionTokens &&
          other.tokensPerSecond == this.tokensPerSecond &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> chatId;
  final Value<String?> parentId;
  final Value<String> role;
  final Value<String> kind;
  final Value<String> content;
  final Value<String?> reasoning;
  final Value<int?> reasoningMs;
  final Value<String?> toolCallsJson;
  final Value<String?> toolCallId;
  final Value<String?> toolName;
  final Value<String?> toolResultJson;
  final Value<String?> attachmentsJson;
  final Value<String?> audioPath;
  final Value<String?> modelRef;
  final Value<String> status;
  final Value<String?> errorText;
  final Value<int?> promptTokens;
  final Value<int?> completionTokens;
  final Value<double?> tokensPerSecond;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.chatId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.role = const Value.absent(),
    this.kind = const Value.absent(),
    this.content = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.reasoningMs = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.toolResultJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.modelRef = const Value.absent(),
    this.status = const Value.absent(),
    this.errorText = const Value.absent(),
    this.promptTokens = const Value.absent(),
    this.completionTokens = const Value.absent(),
    this.tokensPerSecond = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String chatId,
    this.parentId = const Value.absent(),
    required String role,
    this.kind = const Value.absent(),
    this.content = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.reasoningMs = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.toolResultJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.modelRef = const Value.absent(),
    this.status = const Value.absent(),
    this.errorText = const Value.absent(),
    this.promptTokens = const Value.absent(),
    this.completionTokens = const Value.absent(),
    this.tokensPerSecond = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       chatId = Value(chatId),
       role = Value(role);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? chatId,
    Expression<String>? parentId,
    Expression<String>? role,
    Expression<String>? kind,
    Expression<String>? content,
    Expression<String>? reasoning,
    Expression<int>? reasoningMs,
    Expression<String>? toolCallsJson,
    Expression<String>? toolCallId,
    Expression<String>? toolName,
    Expression<String>? toolResultJson,
    Expression<String>? attachmentsJson,
    Expression<String>? audioPath,
    Expression<String>? modelRef,
    Expression<String>? status,
    Expression<String>? errorText,
    Expression<int>? promptTokens,
    Expression<int>? completionTokens,
    Expression<double>? tokensPerSecond,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (chatId != null) 'chat_id': chatId,
      if (parentId != null) 'parent_id': parentId,
      if (role != null) 'role': role,
      if (kind != null) 'kind': kind,
      if (content != null) 'content': content,
      if (reasoning != null) 'reasoning': reasoning,
      if (reasoningMs != null) 'reasoning_ms': reasoningMs,
      if (toolCallsJson != null) 'tool_calls_json': toolCallsJson,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolName != null) 'tool_name': toolName,
      if (toolResultJson != null) 'tool_result_json': toolResultJson,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (audioPath != null) 'audio_path': audioPath,
      if (modelRef != null) 'model_ref': modelRef,
      if (status != null) 'status': status,
      if (errorText != null) 'error_text': errorText,
      if (promptTokens != null) 'prompt_tokens': promptTokens,
      if (completionTokens != null) 'completion_tokens': completionTokens,
      if (tokensPerSecond != null) 'tokens_per_second': tokensPerSecond,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? chatId,
    Value<String?>? parentId,
    Value<String>? role,
    Value<String>? kind,
    Value<String>? content,
    Value<String?>? reasoning,
    Value<int?>? reasoningMs,
    Value<String?>? toolCallsJson,
    Value<String?>? toolCallId,
    Value<String?>? toolName,
    Value<String?>? toolResultJson,
    Value<String?>? attachmentsJson,
    Value<String?>? audioPath,
    Value<String?>? modelRef,
    Value<String>? status,
    Value<String?>? errorText,
    Value<int?>? promptTokens,
    Value<int?>? completionTokens,
    Value<double?>? tokensPerSecond,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      parentId: parentId ?? this.parentId,
      role: role ?? this.role,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      reasoningMs: reasoningMs ?? this.reasoningMs,
      toolCallsJson: toolCallsJson ?? this.toolCallsJson,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      toolResultJson: toolResultJson ?? this.toolResultJson,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      audioPath: audioPath ?? this.audioPath,
      modelRef: modelRef ?? this.modelRef,
      status: status ?? this.status,
      errorText: errorText ?? this.errorText,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (reasoning.present) {
      map['reasoning'] = Variable<String>(reasoning.value);
    }
    if (reasoningMs.present) {
      map['reasoning_ms'] = Variable<int>(reasoningMs.value);
    }
    if (toolCallsJson.present) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson.value);
    }
    if (toolCallId.present) {
      map['tool_call_id'] = Variable<String>(toolCallId.value);
    }
    if (toolName.present) {
      map['tool_name'] = Variable<String>(toolName.value);
    }
    if (toolResultJson.present) {
      map['tool_result_json'] = Variable<String>(toolResultJson.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (modelRef.present) {
      map['model_ref'] = Variable<String>(modelRef.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (errorText.present) {
      map['error_text'] = Variable<String>(errorText.value);
    }
    if (promptTokens.present) {
      map['prompt_tokens'] = Variable<int>(promptTokens.value);
    }
    if (completionTokens.present) {
      map['completion_tokens'] = Variable<int>(completionTokens.value);
    }
    if (tokensPerSecond.present) {
      map['tokens_per_second'] = Variable<double>(tokensPerSecond.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('parentId: $parentId, ')
          ..write('role: $role, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('reasoning: $reasoning, ')
          ..write('reasoningMs: $reasoningMs, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('toolResultJson: $toolResultJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('audioPath: $audioPath, ')
          ..write('modelRef: $modelRef, ')
          ..write('status: $status, ')
          ..write('errorText: $errorText, ')
          ..write('promptTokens: $promptTokens, ')
          ..write('completionTokens: $completionTokens, ')
          ..write('tokensPerSecond: $tokensPerSecond, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoriesTable extends Memories with TableInfo<$MemoriesTable, Memory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('general'),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('global'),
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('user'),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _useCountMeta = const VerificationMeta(
    'useCount',
  );
  @override
  late final GeneratedColumn<int> useCount = GeneratedColumn<int>(
    'use_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _embeddingMeta = const VerificationMeta(
    'embedding',
  );
  @override
  late final GeneratedColumn<Uint8List> embedding = GeneratedColumn<Uint8List>(
    'embedding',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    category,
    scope,
    chatId,
    source,
    pinned,
    enabled,
    useCount,
    lastUsedAt,
    embedding,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Memory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('use_count')) {
      context.handle(
        _useCountMeta,
        useCount.isAcceptableOrUnknown(data['use_count']!, _useCountMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('embedding')) {
      context.handle(
        _embeddingMeta,
        embedding.isAcceptableOrUnknown(data['embedding']!, _embeddingMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Memory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Memory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      useCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}use_count'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
      embedding: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}embedding'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MemoriesTable createAlias(String alias) {
    return $MemoriesTable(attachedDatabase, alias);
  }
}

class Memory extends DataClass implements Insertable<Memory> {
  final String id;
  final String content;
  final String category;
  final String scope;
  final String? chatId;
  final String source;
  final bool pinned;
  final bool enabled;
  final int useCount;
  final DateTime? lastUsedAt;
  final Uint8List? embedding;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Memory({
    required this.id,
    required this.content,
    required this.category,
    required this.scope,
    this.chatId,
    required this.source,
    required this.pinned,
    required this.enabled,
    required this.useCount,
    this.lastUsedAt,
    this.embedding,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    map['category'] = Variable<String>(category);
    map['scope'] = Variable<String>(scope);
    if (!nullToAbsent || chatId != null) {
      map['chat_id'] = Variable<String>(chatId);
    }
    map['source'] = Variable<String>(source);
    map['pinned'] = Variable<bool>(pinned);
    map['enabled'] = Variable<bool>(enabled);
    map['use_count'] = Variable<int>(useCount);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    if (!nullToAbsent || embedding != null) {
      map['embedding'] = Variable<Uint8List>(embedding);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MemoriesCompanion toCompanion(bool nullToAbsent) {
    return MemoriesCompanion(
      id: Value(id),
      content: Value(content),
      category: Value(category),
      scope: Value(scope),
      chatId: chatId == null && nullToAbsent
          ? const Value.absent()
          : Value(chatId),
      source: Value(source),
      pinned: Value(pinned),
      enabled: Value(enabled),
      useCount: Value(useCount),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      embedding: embedding == null && nullToAbsent
          ? const Value.absent()
          : Value(embedding),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Memory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Memory(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      category: serializer.fromJson<String>(json['category']),
      scope: serializer.fromJson<String>(json['scope']),
      chatId: serializer.fromJson<String?>(json['chatId']),
      source: serializer.fromJson<String>(json['source']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      useCount: serializer.fromJson<int>(json['useCount']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      embedding: serializer.fromJson<Uint8List?>(json['embedding']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'category': serializer.toJson<String>(category),
      'scope': serializer.toJson<String>(scope),
      'chatId': serializer.toJson<String?>(chatId),
      'source': serializer.toJson<String>(source),
      'pinned': serializer.toJson<bool>(pinned),
      'enabled': serializer.toJson<bool>(enabled),
      'useCount': serializer.toJson<int>(useCount),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'embedding': serializer.toJson<Uint8List?>(embedding),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Memory copyWith({
    String? id,
    String? content,
    String? category,
    String? scope,
    Value<String?> chatId = const Value.absent(),
    String? source,
    bool? pinned,
    bool? enabled,
    int? useCount,
    Value<DateTime?> lastUsedAt = const Value.absent(),
    Value<Uint8List?> embedding = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Memory(
    id: id ?? this.id,
    content: content ?? this.content,
    category: category ?? this.category,
    scope: scope ?? this.scope,
    chatId: chatId.present ? chatId.value : this.chatId,
    source: source ?? this.source,
    pinned: pinned ?? this.pinned,
    enabled: enabled ?? this.enabled,
    useCount: useCount ?? this.useCount,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
    embedding: embedding.present ? embedding.value : this.embedding,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Memory copyWithCompanion(MemoriesCompanion data) {
    return Memory(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      category: data.category.present ? data.category.value : this.category,
      scope: data.scope.present ? data.scope.value : this.scope,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      source: data.source.present ? data.source.value : this.source,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      useCount: data.useCount.present ? data.useCount.value : this.useCount,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      embedding: data.embedding.present ? data.embedding.value : this.embedding,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Memory(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('scope: $scope, ')
          ..write('chatId: $chatId, ')
          ..write('source: $source, ')
          ..write('pinned: $pinned, ')
          ..write('enabled: $enabled, ')
          ..write('useCount: $useCount, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('embedding: $embedding, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    category,
    scope,
    chatId,
    source,
    pinned,
    enabled,
    useCount,
    lastUsedAt,
    $driftBlobEquality.hash(embedding),
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Memory &&
          other.id == this.id &&
          other.content == this.content &&
          other.category == this.category &&
          other.scope == this.scope &&
          other.chatId == this.chatId &&
          other.source == this.source &&
          other.pinned == this.pinned &&
          other.enabled == this.enabled &&
          other.useCount == this.useCount &&
          other.lastUsedAt == this.lastUsedAt &&
          $driftBlobEquality.equals(other.embedding, this.embedding) &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MemoriesCompanion extends UpdateCompanion<Memory> {
  final Value<String> id;
  final Value<String> content;
  final Value<String> category;
  final Value<String> scope;
  final Value<String?> chatId;
  final Value<String> source;
  final Value<bool> pinned;
  final Value<bool> enabled;
  final Value<int> useCount;
  final Value<DateTime?> lastUsedAt;
  final Value<Uint8List?> embedding;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MemoriesCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.category = const Value.absent(),
    this.scope = const Value.absent(),
    this.chatId = const Value.absent(),
    this.source = const Value.absent(),
    this.pinned = const Value.absent(),
    this.enabled = const Value.absent(),
    this.useCount = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.embedding = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoriesCompanion.insert({
    required String id,
    required String content,
    this.category = const Value.absent(),
    this.scope = const Value.absent(),
    this.chatId = const Value.absent(),
    this.source = const Value.absent(),
    this.pinned = const Value.absent(),
    this.enabled = const Value.absent(),
    this.useCount = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.embedding = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       content = Value(content);
  static Insertable<Memory> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<String>? category,
    Expression<String>? scope,
    Expression<String>? chatId,
    Expression<String>? source,
    Expression<bool>? pinned,
    Expression<bool>? enabled,
    Expression<int>? useCount,
    Expression<DateTime>? lastUsedAt,
    Expression<Uint8List>? embedding,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (category != null) 'category': category,
      if (scope != null) 'scope': scope,
      if (chatId != null) 'chat_id': chatId,
      if (source != null) 'source': source,
      if (pinned != null) 'pinned': pinned,
      if (enabled != null) 'enabled': enabled,
      if (useCount != null) 'use_count': useCount,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (embedding != null) 'embedding': embedding,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? content,
    Value<String>? category,
    Value<String>? scope,
    Value<String?>? chatId,
    Value<String>? source,
    Value<bool>? pinned,
    Value<bool>? enabled,
    Value<int>? useCount,
    Value<DateTime?>? lastUsedAt,
    Value<Uint8List?>? embedding,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MemoriesCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      category: category ?? this.category,
      scope: scope ?? this.scope,
      chatId: chatId ?? this.chatId,
      source: source ?? this.source,
      pinned: pinned ?? this.pinned,
      enabled: enabled ?? this.enabled,
      useCount: useCount ?? this.useCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      embedding: embedding ?? this.embedding,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (useCount.present) {
      map['use_count'] = Variable<int>(useCount.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (embedding.present) {
      map['embedding'] = Variable<Uint8List>(embedding.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoriesCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('scope: $scope, ')
          ..write('chatId: $chatId, ')
          ..write('source: $source, ')
          ..write('pinned: $pinned, ')
          ..write('enabled: $enabled, ')
          ..write('useCount: $useCount, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('embedding: $embedding, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LlmProvidersTable extends LlmProviders
    with TableInfo<$LlmProvidersTable, LlmProvider> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LlmProvidersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _presetMeta = const VerificationMeta('preset');
  @override
  late final GeneratedColumn<String> preset = GeneratedColumn<String>(
    'preset',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _extraJsonMeta = const VerificationMeta(
    'extraJson',
  );
  @override
  late final GeneratedColumn<String> extraJson = GeneratedColumn<String>(
    'extra_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    name,
    baseUrl,
    preset,
    enabled,
    extraJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'llm_providers';
  @override
  VerificationContext validateIntegrity(
    Insertable<LlmProvider> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('preset')) {
      context.handle(
        _presetMeta,
        preset.isAcceptableOrUnknown(data['preset']!, _presetMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('extra_json')) {
      context.handle(
        _extraJsonMeta,
        extraJson.isAcceptableOrUnknown(data['extra_json']!, _extraJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LlmProvider map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LlmProvider(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      preset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      extraJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LlmProvidersTable createAlias(String alias) {
    return $LlmProvidersTable(attachedDatabase, alias);
  }
}

class LlmProvider extends DataClass implements Insertable<LlmProvider> {
  final String id;
  final String kind;
  final String name;
  final String baseUrl;
  final String? preset;
  final bool enabled;
  final String extraJson;
  final DateTime createdAt;
  const LlmProvider({
    required this.id,
    required this.kind,
    required this.name,
    required this.baseUrl,
    this.preset,
    required this.enabled,
    required this.extraJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['base_url'] = Variable<String>(baseUrl);
    if (!nullToAbsent || preset != null) {
      map['preset'] = Variable<String>(preset);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['extra_json'] = Variable<String>(extraJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LlmProvidersCompanion toCompanion(bool nullToAbsent) {
    return LlmProvidersCompanion(
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      baseUrl: Value(baseUrl),
      preset: preset == null && nullToAbsent
          ? const Value.absent()
          : Value(preset),
      enabled: Value(enabled),
      extraJson: Value(extraJson),
      createdAt: Value(createdAt),
    );
  }

  factory LlmProvider.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LlmProvider(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      preset: serializer.fromJson<String?>(json['preset']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      extraJson: serializer.fromJson<String>(json['extraJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'preset': serializer.toJson<String?>(preset),
      'enabled': serializer.toJson<bool>(enabled),
      'extraJson': serializer.toJson<String>(extraJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LlmProvider copyWith({
    String? id,
    String? kind,
    String? name,
    String? baseUrl,
    Value<String?> preset = const Value.absent(),
    bool? enabled,
    String? extraJson,
    DateTime? createdAt,
  }) => LlmProvider(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    preset: preset.present ? preset.value : this.preset,
    enabled: enabled ?? this.enabled,
    extraJson: extraJson ?? this.extraJson,
    createdAt: createdAt ?? this.createdAt,
  );
  LlmProvider copyWithCompanion(LlmProvidersCompanion data) {
    return LlmProvider(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      preset: data.preset.present ? data.preset.value : this.preset,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      extraJson: data.extraJson.present ? data.extraJson.value : this.extraJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LlmProvider(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('preset: $preset, ')
          ..write('enabled: $enabled, ')
          ..write('extraJson: $extraJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    baseUrl,
    preset,
    enabled,
    extraJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmProvider &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.baseUrl == this.baseUrl &&
          other.preset == this.preset &&
          other.enabled == this.enabled &&
          other.extraJson == this.extraJson &&
          other.createdAt == this.createdAt);
}

class LlmProvidersCompanion extends UpdateCompanion<LlmProvider> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> name;
  final Value<String> baseUrl;
  final Value<String?> preset;
  final Value<bool> enabled;
  final Value<String> extraJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LlmProvidersCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.preset = const Value.absent(),
    this.enabled = const Value.absent(),
    this.extraJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LlmProvidersCompanion.insert({
    required String id,
    required String kind,
    required String name,
    required String baseUrl,
    this.preset = const Value.absent(),
    this.enabled = const Value.absent(),
    this.extraJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       name = Value(name),
       baseUrl = Value(baseUrl);
  static Insertable<LlmProvider> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? baseUrl,
    Expression<String>? preset,
    Expression<bool>? enabled,
    Expression<String>? extraJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (baseUrl != null) 'base_url': baseUrl,
      if (preset != null) 'preset': preset,
      if (enabled != null) 'enabled': enabled,
      if (extraJson != null) 'extra_json': extraJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LlmProvidersCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? name,
    Value<String>? baseUrl,
    Value<String?>? preset,
    Value<bool>? enabled,
    Value<String>? extraJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LlmProvidersCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      preset: preset ?? this.preset,
      enabled: enabled ?? this.enabled,
      extraJson: extraJson ?? this.extraJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (preset.present) {
      map['preset'] = Variable<String>(preset.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (extraJson.present) {
      map['extra_json'] = Variable<String>(extraJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LlmProvidersCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('preset: $preset, ')
          ..write('enabled: $enabled, ')
          ..write('extraJson: $extraJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LlmModelsTable extends LlmModels
    with TableInfo<$LlmModelsTable, LlmModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LlmModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES llm_providers (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capsJsonMeta = const VerificationMeta(
    'capsJson',
  );
  @override
  late final GeneratedColumn<String> capsJson = GeneratedColumn<String>(
    'caps_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _overridesJsonMeta = const VerificationMeta(
    'overridesJson',
  );
  @override
  late final GeneratedColumn<String> overridesJson = GeneratedColumn<String>(
    'overrides_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    providerId,
    modelId,
    displayName,
    capsJson,
    overridesJson,
    hidden,
    favorite,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'llm_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<LlmModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('caps_json')) {
      context.handle(
        _capsJsonMeta,
        capsJson.isAcceptableOrUnknown(data['caps_json']!, _capsJsonMeta),
      );
    }
    if (data.containsKey('overrides_json')) {
      context.handle(
        _overridesJsonMeta,
        overridesJson.isAcceptableOrUnknown(
          data['overrides_json']!,
          _overridesJsonMeta,
        ),
      );
    }
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LlmModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LlmModel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      capsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caps_json'],
      )!,
      overridesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overrides_json'],
      )!,
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
    );
  }

  @override
  $LlmModelsTable createAlias(String alias) {
    return $LlmModelsTable(attachedDatabase, alias);
  }
}

class LlmModel extends DataClass implements Insertable<LlmModel> {
  final String id;
  final String providerId;
  final String modelId;
  final String displayName;
  final String capsJson;
  final String overridesJson;
  final bool hidden;
  final bool favorite;
  const LlmModel({
    required this.id,
    required this.providerId,
    required this.modelId,
    required this.displayName,
    required this.capsJson,
    required this.overridesJson,
    required this.hidden,
    required this.favorite,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['provider_id'] = Variable<String>(providerId);
    map['model_id'] = Variable<String>(modelId);
    map['display_name'] = Variable<String>(displayName);
    map['caps_json'] = Variable<String>(capsJson);
    map['overrides_json'] = Variable<String>(overridesJson);
    map['hidden'] = Variable<bool>(hidden);
    map['favorite'] = Variable<bool>(favorite);
    return map;
  }

  LlmModelsCompanion toCompanion(bool nullToAbsent) {
    return LlmModelsCompanion(
      id: Value(id),
      providerId: Value(providerId),
      modelId: Value(modelId),
      displayName: Value(displayName),
      capsJson: Value(capsJson),
      overridesJson: Value(overridesJson),
      hidden: Value(hidden),
      favorite: Value(favorite),
    );
  }

  factory LlmModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LlmModel(
      id: serializer.fromJson<String>(json['id']),
      providerId: serializer.fromJson<String>(json['providerId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      capsJson: serializer.fromJson<String>(json['capsJson']),
      overridesJson: serializer.fromJson<String>(json['overridesJson']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      favorite: serializer.fromJson<bool>(json['favorite']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'providerId': serializer.toJson<String>(providerId),
      'modelId': serializer.toJson<String>(modelId),
      'displayName': serializer.toJson<String>(displayName),
      'capsJson': serializer.toJson<String>(capsJson),
      'overridesJson': serializer.toJson<String>(overridesJson),
      'hidden': serializer.toJson<bool>(hidden),
      'favorite': serializer.toJson<bool>(favorite),
    };
  }

  LlmModel copyWith({
    String? id,
    String? providerId,
    String? modelId,
    String? displayName,
    String? capsJson,
    String? overridesJson,
    bool? hidden,
    bool? favorite,
  }) => LlmModel(
    id: id ?? this.id,
    providerId: providerId ?? this.providerId,
    modelId: modelId ?? this.modelId,
    displayName: displayName ?? this.displayName,
    capsJson: capsJson ?? this.capsJson,
    overridesJson: overridesJson ?? this.overridesJson,
    hidden: hidden ?? this.hidden,
    favorite: favorite ?? this.favorite,
  );
  LlmModel copyWithCompanion(LlmModelsCompanion data) {
    return LlmModel(
      id: data.id.present ? data.id.value : this.id,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      capsJson: data.capsJson.present ? data.capsJson.value : this.capsJson,
      overridesJson: data.overridesJson.present
          ? data.overridesJson.value
          : this.overridesJson,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LlmModel(')
          ..write('id: $id, ')
          ..write('providerId: $providerId, ')
          ..write('modelId: $modelId, ')
          ..write('displayName: $displayName, ')
          ..write('capsJson: $capsJson, ')
          ..write('overridesJson: $overridesJson, ')
          ..write('hidden: $hidden, ')
          ..write('favorite: $favorite')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    providerId,
    modelId,
    displayName,
    capsJson,
    overridesJson,
    hidden,
    favorite,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmModel &&
          other.id == this.id &&
          other.providerId == this.providerId &&
          other.modelId == this.modelId &&
          other.displayName == this.displayName &&
          other.capsJson == this.capsJson &&
          other.overridesJson == this.overridesJson &&
          other.hidden == this.hidden &&
          other.favorite == this.favorite);
}

class LlmModelsCompanion extends UpdateCompanion<LlmModel> {
  final Value<String> id;
  final Value<String> providerId;
  final Value<String> modelId;
  final Value<String> displayName;
  final Value<String> capsJson;
  final Value<String> overridesJson;
  final Value<bool> hidden;
  final Value<bool> favorite;
  final Value<int> rowid;
  const LlmModelsCompanion({
    this.id = const Value.absent(),
    this.providerId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.capsJson = const Value.absent(),
    this.overridesJson = const Value.absent(),
    this.hidden = const Value.absent(),
    this.favorite = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LlmModelsCompanion.insert({
    required String id,
    required String providerId,
    required String modelId,
    required String displayName,
    this.capsJson = const Value.absent(),
    this.overridesJson = const Value.absent(),
    this.hidden = const Value.absent(),
    this.favorite = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       providerId = Value(providerId),
       modelId = Value(modelId),
       displayName = Value(displayName);
  static Insertable<LlmModel> custom({
    Expression<String>? id,
    Expression<String>? providerId,
    Expression<String>? modelId,
    Expression<String>? displayName,
    Expression<String>? capsJson,
    Expression<String>? overridesJson,
    Expression<bool>? hidden,
    Expression<bool>? favorite,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (providerId != null) 'provider_id': providerId,
      if (modelId != null) 'model_id': modelId,
      if (displayName != null) 'display_name': displayName,
      if (capsJson != null) 'caps_json': capsJson,
      if (overridesJson != null) 'overrides_json': overridesJson,
      if (hidden != null) 'hidden': hidden,
      if (favorite != null) 'favorite': favorite,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LlmModelsCompanion copyWith({
    Value<String>? id,
    Value<String>? providerId,
    Value<String>? modelId,
    Value<String>? displayName,
    Value<String>? capsJson,
    Value<String>? overridesJson,
    Value<bool>? hidden,
    Value<bool>? favorite,
    Value<int>? rowid,
  }) {
    return LlmModelsCompanion(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      capsJson: capsJson ?? this.capsJson,
      overridesJson: overridesJson ?? this.overridesJson,
      hidden: hidden ?? this.hidden,
      favorite: favorite ?? this.favorite,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (capsJson.present) {
      map['caps_json'] = Variable<String>(capsJson.value);
    }
    if (overridesJson.present) {
      map['overrides_json'] = Variable<String>(overridesJson.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LlmModelsCompanion(')
          ..write('id: $id, ')
          ..write('providerId: $providerId, ')
          ..write('modelId: $modelId, ')
          ..write('displayName: $displayName, ')
          ..write('capsJson: $capsJson, ')
          ..write('overridesJson: $overridesJson, ')
          ..write('hidden: $hidden, ')
          ..write('favorite: $favorite, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $McpServersTable extends McpServers
    with TableInfo<$McpServersTable, McpServer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $McpServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transportMeta = const VerificationMeta(
    'transport',
  );
  @override
  late final GeneratedColumn<String> transport = GeneratedColumn<String>(
    'transport',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('http'),
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _toolsCacheJsonMeta = const VerificationMeta(
    'toolsCacheJson',
  );
  @override
  late final GeneratedColumn<String> toolsCacheJson = GeneratedColumn<String>(
    'tools_cache_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _disabledToolsJsonMeta = const VerificationMeta(
    'disabledToolsJson',
  );
  @override
  late final GeneratedColumn<String> disabledToolsJson =
      GeneratedColumn<String>(
        'disabled_tools_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    transport,
    url,
    enabled,
    toolsCacheJson,
    disabledToolsJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mcp_servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<McpServer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('transport')) {
      context.handle(
        _transportMeta,
        transport.isAcceptableOrUnknown(data['transport']!, _transportMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('tools_cache_json')) {
      context.handle(
        _toolsCacheJsonMeta,
        toolsCacheJson.isAcceptableOrUnknown(
          data['tools_cache_json']!,
          _toolsCacheJsonMeta,
        ),
      );
    }
    if (data.containsKey('disabled_tools_json')) {
      context.handle(
        _disabledToolsJsonMeta,
        disabledToolsJson.isAcceptableOrUnknown(
          data['disabled_tools_json']!,
          _disabledToolsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  McpServer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return McpServer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      transport: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transport'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      toolsCacheJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tools_cache_json'],
      )!,
      disabledToolsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disabled_tools_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $McpServersTable createAlias(String alias) {
    return $McpServersTable(attachedDatabase, alias);
  }
}

class McpServer extends DataClass implements Insertable<McpServer> {
  final String id;
  final String name;
  final String transport;
  final String url;
  final bool enabled;
  final String toolsCacheJson;
  final String disabledToolsJson;
  final DateTime createdAt;
  const McpServer({
    required this.id,
    required this.name,
    required this.transport,
    required this.url,
    required this.enabled,
    required this.toolsCacheJson,
    required this.disabledToolsJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['transport'] = Variable<String>(transport);
    map['url'] = Variable<String>(url);
    map['enabled'] = Variable<bool>(enabled);
    map['tools_cache_json'] = Variable<String>(toolsCacheJson);
    map['disabled_tools_json'] = Variable<String>(disabledToolsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  McpServersCompanion toCompanion(bool nullToAbsent) {
    return McpServersCompanion(
      id: Value(id),
      name: Value(name),
      transport: Value(transport),
      url: Value(url),
      enabled: Value(enabled),
      toolsCacheJson: Value(toolsCacheJson),
      disabledToolsJson: Value(disabledToolsJson),
      createdAt: Value(createdAt),
    );
  }

  factory McpServer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return McpServer(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      transport: serializer.fromJson<String>(json['transport']),
      url: serializer.fromJson<String>(json['url']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      toolsCacheJson: serializer.fromJson<String>(json['toolsCacheJson']),
      disabledToolsJson: serializer.fromJson<String>(json['disabledToolsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'transport': serializer.toJson<String>(transport),
      'url': serializer.toJson<String>(url),
      'enabled': serializer.toJson<bool>(enabled),
      'toolsCacheJson': serializer.toJson<String>(toolsCacheJson),
      'disabledToolsJson': serializer.toJson<String>(disabledToolsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  McpServer copyWith({
    String? id,
    String? name,
    String? transport,
    String? url,
    bool? enabled,
    String? toolsCacheJson,
    String? disabledToolsJson,
    DateTime? createdAt,
  }) => McpServer(
    id: id ?? this.id,
    name: name ?? this.name,
    transport: transport ?? this.transport,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
    toolsCacheJson: toolsCacheJson ?? this.toolsCacheJson,
    disabledToolsJson: disabledToolsJson ?? this.disabledToolsJson,
    createdAt: createdAt ?? this.createdAt,
  );
  McpServer copyWithCompanion(McpServersCompanion data) {
    return McpServer(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      transport: data.transport.present ? data.transport.value : this.transport,
      url: data.url.present ? data.url.value : this.url,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      toolsCacheJson: data.toolsCacheJson.present
          ? data.toolsCacheJson.value
          : this.toolsCacheJson,
      disabledToolsJson: data.disabledToolsJson.present
          ? data.disabledToolsJson.value
          : this.disabledToolsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('McpServer(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('transport: $transport, ')
          ..write('url: $url, ')
          ..write('enabled: $enabled, ')
          ..write('toolsCacheJson: $toolsCacheJson, ')
          ..write('disabledToolsJson: $disabledToolsJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    transport,
    url,
    enabled,
    toolsCacheJson,
    disabledToolsJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is McpServer &&
          other.id == this.id &&
          other.name == this.name &&
          other.transport == this.transport &&
          other.url == this.url &&
          other.enabled == this.enabled &&
          other.toolsCacheJson == this.toolsCacheJson &&
          other.disabledToolsJson == this.disabledToolsJson &&
          other.createdAt == this.createdAt);
}

class McpServersCompanion extends UpdateCompanion<McpServer> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> transport;
  final Value<String> url;
  final Value<bool> enabled;
  final Value<String> toolsCacheJson;
  final Value<String> disabledToolsJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const McpServersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.transport = const Value.absent(),
    this.url = const Value.absent(),
    this.enabled = const Value.absent(),
    this.toolsCacheJson = const Value.absent(),
    this.disabledToolsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  McpServersCompanion.insert({
    required String id,
    required String name,
    this.transport = const Value.absent(),
    required String url,
    this.enabled = const Value.absent(),
    this.toolsCacheJson = const Value.absent(),
    this.disabledToolsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       url = Value(url);
  static Insertable<McpServer> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? transport,
    Expression<String>? url,
    Expression<bool>? enabled,
    Expression<String>? toolsCacheJson,
    Expression<String>? disabledToolsJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (transport != null) 'transport': transport,
      if (url != null) 'url': url,
      if (enabled != null) 'enabled': enabled,
      if (toolsCacheJson != null) 'tools_cache_json': toolsCacheJson,
      if (disabledToolsJson != null) 'disabled_tools_json': disabledToolsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  McpServersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? transport,
    Value<String>? url,
    Value<bool>? enabled,
    Value<String>? toolsCacheJson,
    Value<String>? disabledToolsJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return McpServersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      toolsCacheJson: toolsCacheJson ?? this.toolsCacheJson,
      disabledToolsJson: disabledToolsJson ?? this.disabledToolsJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (transport.present) {
      map['transport'] = Variable<String>(transport.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (toolsCacheJson.present) {
      map['tools_cache_json'] = Variable<String>(toolsCacheJson.value);
    }
    if (disabledToolsJson.present) {
      map['disabled_tools_json'] = Variable<String>(disabledToolsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('McpServersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('transport: $transport, ')
          ..write('url: $url, ')
          ..write('enabled: $enabled, ')
          ..write('toolsCacheJson: $toolsCacheJson, ')
          ..write('disabledToolsJson: $disabledToolsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillsTable extends Skills with TableInfo<$SkillsTable, Skill> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _dirMeta = const VerificationMeta('dir');
  @override
  late final GeneratedColumn<String> dir = GeneratedColumn<String>(
    'dir',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    body,
    source,
    dir,
    enabled,
    installedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skills';
  @override
  VerificationContext validateIntegrity(
    Insertable<Skill> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('dir')) {
      context.handle(
        _dirMeta,
        dir.isAcceptableOrUnknown(data['dir']!, _dirMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Skill map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Skill(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      dir: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dir'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
    );
  }

  @override
  $SkillsTable createAlias(String alias) {
    return $SkillsTable(attachedDatabase, alias);
  }
}

class Skill extends DataClass implements Insertable<Skill> {
  final String id;
  final String name;
  final String description;
  final String body;
  final String source;
  final String? dir;
  final bool enabled;
  final DateTime installedAt;
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
    required this.source,
    this.dir,
    required this.enabled,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['body'] = Variable<String>(body);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || dir != null) {
      map['dir'] = Variable<String>(dir);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['installed_at'] = Variable<DateTime>(installedAt);
    return map;
  }

  SkillsCompanion toCompanion(bool nullToAbsent) {
    return SkillsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      body: Value(body),
      source: Value(source),
      dir: dir == null && nullToAbsent ? const Value.absent() : Value(dir),
      enabled: Value(enabled),
      installedAt: Value(installedAt),
    );
  }

  factory Skill.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Skill(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      body: serializer.fromJson<String>(json['body']),
      source: serializer.fromJson<String>(json['source']),
      dir: serializer.fromJson<String?>(json['dir']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'body': serializer.toJson<String>(body),
      'source': serializer.toJson<String>(source),
      'dir': serializer.toJson<String?>(dir),
      'enabled': serializer.toJson<bool>(enabled),
      'installedAt': serializer.toJson<DateTime>(installedAt),
    };
  }

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? body,
    String? source,
    Value<String?> dir = const Value.absent(),
    bool? enabled,
    DateTime? installedAt,
  }) => Skill(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    body: body ?? this.body,
    source: source ?? this.source,
    dir: dir.present ? dir.value : this.dir,
    enabled: enabled ?? this.enabled,
    installedAt: installedAt ?? this.installedAt,
  );
  Skill copyWithCompanion(SkillsCompanion data) {
    return Skill(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      body: data.body.present ? data.body.value : this.body,
      source: data.source.present ? data.source.value : this.source,
      dir: data.dir.present ? data.dir.value : this.dir,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Skill(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('body: $body, ')
          ..write('source: $source, ')
          ..write('dir: $dir, ')
          ..write('enabled: $enabled, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    body,
    source,
    dir,
    enabled,
    installedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Skill &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.body == this.body &&
          other.source == this.source &&
          other.dir == this.dir &&
          other.enabled == this.enabled &&
          other.installedAt == this.installedAt);
}

class SkillsCompanion extends UpdateCompanion<Skill> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> body;
  final Value<String> source;
  final Value<String?> dir;
  final Value<bool> enabled;
  final Value<DateTime> installedAt;
  final Value<int> rowid;
  const SkillsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.body = const Value.absent(),
    this.source = const Value.absent(),
    this.dir = const Value.absent(),
    this.enabled = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SkillsCompanion.insert({
    required String id,
    required String name,
    required String description,
    required String body,
    this.source = const Value.absent(),
    this.dir = const Value.absent(),
    this.enabled = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       description = Value(description),
       body = Value(body);
  static Insertable<Skill> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? body,
    Expression<String>? source,
    Expression<String>? dir,
    Expression<bool>? enabled,
    Expression<DateTime>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (body != null) 'body': body,
      if (source != null) 'source': source,
      if (dir != null) 'dir': dir,
      if (enabled != null) 'enabled': enabled,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SkillsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? description,
    Value<String>? body,
    Value<String>? source,
    Value<String?>? dir,
    Value<bool>? enabled,
    Value<DateTime>? installedAt,
    Value<int>? rowid,
  }) {
    return SkillsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      body: body ?? this.body,
      source: source ?? this.source,
      dir: dir ?? this.dir,
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (dir.present) {
      map['dir'] = Variable<String>(dir.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('body: $body, ')
          ..write('source: $source, ')
          ..write('dir: $dir, ')
          ..write('enabled: $enabled, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NasDevicesTable extends NasDevices
    with TableInfo<$NasDevicesTable, NasDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NasDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _infoJsonMeta = const VerificationMeta(
    'infoJson',
  );
  @override
  late final GeneratedColumn<String> infoJson = GeneratedColumn<String>(
    'info_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    baseUrl,
    infoJson,
    isDefault,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nas_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<NasDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('info_json')) {
      context.handle(
        _infoJsonMeta,
        infoJson.isAcceptableOrUnknown(data['info_json']!, _infoJsonMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NasDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NasDevice(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      infoJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}info_json'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      ),
    );
  }

  @override
  $NasDevicesTable createAlias(String alias) {
    return $NasDevicesTable(attachedDatabase, alias);
  }
}

class NasDevice extends DataClass implements Insertable<NasDevice> {
  final String id;
  final String name;
  final String baseUrl;
  final String infoJson;
  final bool isDefault;
  final DateTime? lastSeen;
  const NasDevice({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.infoJson,
    required this.isDefault,
    this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['base_url'] = Variable<String>(baseUrl);
    map['info_json'] = Variable<String>(infoJson);
    map['is_default'] = Variable<bool>(isDefault);
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    return map;
  }

  NasDevicesCompanion toCompanion(bool nullToAbsent) {
    return NasDevicesCompanion(
      id: Value(id),
      name: Value(name),
      baseUrl: Value(baseUrl),
      infoJson: Value(infoJson),
      isDefault: Value(isDefault),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
    );
  }

  factory NasDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NasDevice(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      infoJson: serializer.fromJson<String>(json['infoJson']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'infoJson': serializer.toJson<String>(infoJson),
      'isDefault': serializer.toJson<bool>(isDefault),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
    };
  }

  NasDevice copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? infoJson,
    bool? isDefault,
    Value<DateTime?> lastSeen = const Value.absent(),
  }) => NasDevice(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    infoJson: infoJson ?? this.infoJson,
    isDefault: isDefault ?? this.isDefault,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
  );
  NasDevice copyWithCompanion(NasDevicesCompanion data) {
    return NasDevice(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      infoJson: data.infoJson.present ? data.infoJson.value : this.infoJson,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NasDevice(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('infoJson: $infoJson, ')
          ..write('isDefault: $isDefault, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, baseUrl, infoJson, isDefault, lastSeen);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NasDevice &&
          other.id == this.id &&
          other.name == this.name &&
          other.baseUrl == this.baseUrl &&
          other.infoJson == this.infoJson &&
          other.isDefault == this.isDefault &&
          other.lastSeen == this.lastSeen);
}

class NasDevicesCompanion extends UpdateCompanion<NasDevice> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> baseUrl;
  final Value<String> infoJson;
  final Value<bool> isDefault;
  final Value<DateTime?> lastSeen;
  final Value<int> rowid;
  const NasDevicesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.infoJson = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NasDevicesCompanion.insert({
    required String id,
    required String name,
    required String baseUrl,
    this.infoJson = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       baseUrl = Value(baseUrl);
  static Insertable<NasDevice> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? baseUrl,
    Expression<String>? infoJson,
    Expression<bool>? isDefault,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (baseUrl != null) 'base_url': baseUrl,
      if (infoJson != null) 'info_json': infoJson,
      if (isDefault != null) 'is_default': isDefault,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NasDevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? baseUrl,
    Value<String>? infoJson,
    Value<bool>? isDefault,
    Value<DateTime?>? lastSeen,
    Value<int>? rowid,
  }) {
    return NasDevicesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      infoJson: infoJson ?? this.infoJson,
      isDefault: isDefault ?? this.isDefault,
      lastSeen: lastSeen ?? this.lastSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (infoJson.present) {
      map['info_json'] = Variable<String>(infoJson.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NasDevicesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('infoJson: $infoJson, ')
          ..write('isDefault: $isDefault, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $ChatsTable chats = $ChatsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $MemoriesTable memories = $MemoriesTable(this);
  late final $LlmProvidersTable llmProviders = $LlmProvidersTable(this);
  late final $LlmModelsTable llmModels = $LlmModelsTable(this);
  late final $McpServersTable mcpServers = $McpServersTable(this);
  late final $SkillsTable skills = $SkillsTable(this);
  late final $NasDevicesTable nasDevices = $NasDevicesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chats,
    messages,
    memories,
    llmProviders,
    llmModels,
    mcpServers,
    skills,
    nasDevices,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'chats',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'llm_providers',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('llm_models', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ChatsTableCreateCompanionBuilder =
    ChatsCompanion Function({
      required String id,
      Value<String> title,
      Value<String?> modelRef,
      Value<String?> systemPrompt,
      Value<String> settingsJson,
      Value<String?> activeLeafId,
      Value<String?> folder,
      Value<bool> pinned,
      Value<bool> archived,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ChatsTableUpdateCompanionBuilder =
    ChatsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> modelRef,
      Value<String?> systemPrompt,
      Value<String> settingsJson,
      Value<String?> activeLeafId,
      Value<String?> folder,
      Value<bool> pinned,
      Value<bool> archived,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ChatsTableReferences
    extends BaseReferences<_$AppDb, $ChatsTable, Chat> {
  $$ChatsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDb db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'chats__id__messages__chat_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.chatId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChatsTableFilterComposer extends Composer<_$AppDb, $ChatsTable> {
  $$ChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelRef => $composableBuilder(
    column: $table.modelRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeLeafId => $composableBuilder(
    column: $table.activeLeafId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folder => $composableBuilder(
    column: $table.folder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatsTableOrderingComposer extends Composer<_$AppDb, $ChatsTable> {
  $$ChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelRef => $composableBuilder(
    column: $table.modelRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeLeafId => $composableBuilder(
    column: $table.activeLeafId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folder => $composableBuilder(
    column: $table.folder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatsTableAnnotationComposer extends Composer<_$AppDb, $ChatsTable> {
  $$ChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get modelRef =>
      $composableBuilder(column: $table.modelRef, builder: (column) => column);

  GeneratedColumn<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activeLeafId => $composableBuilder(
    column: $table.activeLeafId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get folder =>
      $composableBuilder(column: $table.folder, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $ChatsTable,
          Chat,
          $$ChatsTableFilterComposer,
          $$ChatsTableOrderingComposer,
          $$ChatsTableAnnotationComposer,
          $$ChatsTableCreateCompanionBuilder,
          $$ChatsTableUpdateCompanionBuilder,
          (Chat, $$ChatsTableReferences),
          Chat,
          PrefetchHooks Function({bool messagesRefs})
        > {
  $$ChatsTableTableManager(_$AppDb db, $ChatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> modelRef = const Value.absent(),
                Value<String?> systemPrompt = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
                Value<String?> activeLeafId = const Value.absent(),
                Value<String?> folder = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatsCompanion(
                id: id,
                title: title,
                modelRef: modelRef,
                systemPrompt: systemPrompt,
                settingsJson: settingsJson,
                activeLeafId: activeLeafId,
                folder: folder,
                pinned: pinned,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String?> modelRef = const Value.absent(),
                Value<String?> systemPrompt = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
                Value<String?> activeLeafId = const Value.absent(),
                Value<String?> folder = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatsCompanion.insert(
                id: id,
                title: title,
                modelRef: modelRef,
                systemPrompt: systemPrompt,
                settingsJson: settingsJson,
                activeLeafId: activeLeafId,
                folder: folder,
                pinned: pinned,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatsTable, Chat>(table),
                  $$ChatsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<Chat, $ChatsTable, Message>(
                      currentTable: table,
                      referencedTable: $$ChatsTableReferences
                          ._messagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ChatsTableReferences(db, table, p0).messagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.chatId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $ChatsTable,
      Chat,
      $$ChatsTableFilterComposer,
      $$ChatsTableOrderingComposer,
      $$ChatsTableAnnotationComposer,
      $$ChatsTableCreateCompanionBuilder,
      $$ChatsTableUpdateCompanionBuilder,
      (Chat, $$ChatsTableReferences),
      Chat,
      PrefetchHooks Function({bool messagesRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String chatId,
      Value<String?> parentId,
      required String role,
      Value<String> kind,
      Value<String> content,
      Value<String?> reasoning,
      Value<int?> reasoningMs,
      Value<String?> toolCallsJson,
      Value<String?> toolCallId,
      Value<String?> toolName,
      Value<String?> toolResultJson,
      Value<String?> attachmentsJson,
      Value<String?> audioPath,
      Value<String?> modelRef,
      Value<String> status,
      Value<String?> errorText,
      Value<int?> promptTokens,
      Value<int?> completionTokens,
      Value<double?> tokensPerSecond,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> chatId,
      Value<String?> parentId,
      Value<String> role,
      Value<String> kind,
      Value<String> content,
      Value<String?> reasoning,
      Value<int?> reasoningMs,
      Value<String?> toolCallsJson,
      Value<String?> toolCallId,
      Value<String?> toolName,
      Value<String?> toolResultJson,
      Value<String?> attachmentsJson,
      Value<String?> audioPath,
      Value<String?> modelRef,
      Value<String> status,
      Value<String?> errorText,
      Value<int?> promptTokens,
      Value<int?> completionTokens,
      Value<double?> tokensPerSecond,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDb, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChatsTable _chatIdTable(_$AppDb db) =>
      db.chats.createAlias('messages__chat_id__chats__id');

  $$ChatsTableProcessedTableManager get chatId {
    final $_column = $_itemColumn<String>('chat_id')!;

    final manager = $$ChatsTableTableManager(
      $_db,
      $_db.chats,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chatIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer extends Composer<_$AppDb, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reasoningMs => $composableBuilder(
    column: $table.reasoningMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolResultJson => $composableBuilder(
    column: $table.toolResultJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelRef => $composableBuilder(
    column: $table.modelRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorText => $composableBuilder(
    column: $table.errorText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tokensPerSecond => $composableBuilder(
    column: $table.tokensPerSecond,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChatsTableFilterComposer get chatId {
    final $$ChatsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.chats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatsTableFilterComposer(
            $db: $db,
            $table: $db.chats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDb, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reasoningMs => $composableBuilder(
    column: $table.reasoningMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolResultJson => $composableBuilder(
    column: $table.toolResultJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelRef => $composableBuilder(
    column: $table.modelRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorText => $composableBuilder(
    column: $table.errorText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tokensPerSecond => $composableBuilder(
    column: $table.tokensPerSecond,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChatsTableOrderingComposer get chatId {
    final $$ChatsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.chats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatsTableOrderingComposer(
            $db: $db,
            $table: $db.chats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDb, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get reasoning =>
      $composableBuilder(column: $table.reasoning, builder: (column) => column);

  GeneratedColumn<int> get reasoningMs => $composableBuilder(
    column: $table.reasoningMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toolName =>
      $composableBuilder(column: $table.toolName, builder: (column) => column);

  GeneratedColumn<String> get toolResultJson => $composableBuilder(
    column: $table.toolResultJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<String> get modelRef =>
      $composableBuilder(column: $table.modelRef, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorText =>
      $composableBuilder(column: $table.errorText, builder: (column) => column);

  GeneratedColumn<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => column,
  );

  GeneratedColumn<double> get tokensPerSecond => $composableBuilder(
    column: $table.tokensPerSecond,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ChatsTableAnnotationComposer get chatId {
    final $$ChatsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.chats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatsTableAnnotationComposer(
            $db: $db,
            $table: $db.chats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool chatId})
        > {
  $$MessagesTableTableManager(_$AppDb db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<int?> reasoningMs = const Value.absent(),
                Value<String?> toolCallsJson = const Value.absent(),
                Value<String?> toolCallId = const Value.absent(),
                Value<String?> toolName = const Value.absent(),
                Value<String?> toolResultJson = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<String?> modelRef = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> errorText = const Value.absent(),
                Value<int?> promptTokens = const Value.absent(),
                Value<int?> completionTokens = const Value.absent(),
                Value<double?> tokensPerSecond = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                chatId: chatId,
                parentId: parentId,
                role: role,
                kind: kind,
                content: content,
                reasoning: reasoning,
                reasoningMs: reasoningMs,
                toolCallsJson: toolCallsJson,
                toolCallId: toolCallId,
                toolName: toolName,
                toolResultJson: toolResultJson,
                attachmentsJson: attachmentsJson,
                audioPath: audioPath,
                modelRef: modelRef,
                status: status,
                errorText: errorText,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                tokensPerSecond: tokensPerSecond,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String chatId,
                Value<String?> parentId = const Value.absent(),
                required String role,
                Value<String> kind = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<int?> reasoningMs = const Value.absent(),
                Value<String?> toolCallsJson = const Value.absent(),
                Value<String?> toolCallId = const Value.absent(),
                Value<String?> toolName = const Value.absent(),
                Value<String?> toolResultJson = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<String?> modelRef = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> errorText = const Value.absent(),
                Value<int?> promptTokens = const Value.absent(),
                Value<int?> completionTokens = const Value.absent(),
                Value<double?> tokensPerSecond = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                chatId: chatId,
                parentId: parentId,
                role: role,
                kind: kind,
                content: content,
                reasoning: reasoning,
                reasoningMs: reasoningMs,
                toolCallsJson: toolCallsJson,
                toolCallId: toolCallId,
                toolName: toolName,
                toolResultJson: toolResultJson,
                attachmentsJson: attachmentsJson,
                audioPath: audioPath,
                modelRef: modelRef,
                status: status,
                errorText: errorText,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                tokensPerSecond: tokensPerSecond,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (chatId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.chatId,
                                referencedTable: $$MessagesTableReferences
                                    ._chatIdTable(db),
                                referencedColumn: $$MessagesTableReferences
                                    ._chatIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool chatId})
    >;
typedef $$MemoriesTableCreateCompanionBuilder =
    MemoriesCompanion Function({
      required String id,
      required String content,
      Value<String> category,
      Value<String> scope,
      Value<String?> chatId,
      Value<String> source,
      Value<bool> pinned,
      Value<bool> enabled,
      Value<int> useCount,
      Value<DateTime?> lastUsedAt,
      Value<Uint8List?> embedding,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$MemoriesTableUpdateCompanionBuilder =
    MemoriesCompanion Function({
      Value<String> id,
      Value<String> content,
      Value<String> category,
      Value<String> scope,
      Value<String?> chatId,
      Value<String> source,
      Value<bool> pinned,
      Value<bool> enabled,
      Value<int> useCount,
      Value<DateTime?> lastUsedAt,
      Value<Uint8List?> embedding,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MemoriesTableFilterComposer extends Composer<_$AppDb, $MemoriesTable> {
  $$MemoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoriesTableOrderingComposer
    extends Composer<_$AppDb, $MemoriesTable> {
  $$MemoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chatId => $composableBuilder(
    column: $table.chatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoriesTableAnnotationComposer
    extends Composer<_$AppDb, $MemoriesTable> {
  $$MemoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get embedding =>
      $composableBuilder(column: $table.embedding, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MemoriesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $MemoriesTable,
          Memory,
          $$MemoriesTableFilterComposer,
          $$MemoriesTableOrderingComposer,
          $$MemoriesTableAnnotationComposer,
          $$MemoriesTableCreateCompanionBuilder,
          $$MemoriesTableUpdateCompanionBuilder,
          (Memory, BaseReferences<_$AppDb, $MemoriesTable, Memory>),
          Memory,
          PrefetchHooks Function()
        > {
  $$MemoriesTableTableManager(_$AppDb db, $MemoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String?> chatId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<Uint8List?> embedding = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion(
                id: id,
                content: content,
                category: category,
                scope: scope,
                chatId: chatId,
                source: source,
                pinned: pinned,
                enabled: enabled,
                useCount: useCount,
                lastUsedAt: lastUsedAt,
                embedding: embedding,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String content,
                Value<String> category = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String?> chatId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<Uint8List?> embedding = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion.insert(
                id: id,
                content: content,
                category: category,
                scope: scope,
                chatId: chatId,
                source: source,
                pinned: pinned,
                enabled: enabled,
                useCount: useCount,
                lastUsedAt: lastUsedAt,
                embedding: embedding,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MemoriesTable, Memory>(table),
                  BaseReferences<_$AppDb, $MemoriesTable, Memory>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $MemoriesTable,
      Memory,
      $$MemoriesTableFilterComposer,
      $$MemoriesTableOrderingComposer,
      $$MemoriesTableAnnotationComposer,
      $$MemoriesTableCreateCompanionBuilder,
      $$MemoriesTableUpdateCompanionBuilder,
      (Memory, BaseReferences<_$AppDb, $MemoriesTable, Memory>),
      Memory,
      PrefetchHooks Function()
    >;
typedef $$LlmProvidersTableCreateCompanionBuilder =
    LlmProvidersCompanion Function({
      required String id,
      required String kind,
      required String name,
      required String baseUrl,
      Value<String?> preset,
      Value<bool> enabled,
      Value<String> extraJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$LlmProvidersTableUpdateCompanionBuilder =
    LlmProvidersCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String> name,
      Value<String> baseUrl,
      Value<String?> preset,
      Value<bool> enabled,
      Value<String> extraJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$LlmProvidersTableReferences
    extends BaseReferences<_$AppDb, $LlmProvidersTable, LlmProvider> {
  $$LlmProvidersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LlmModelsTable, List<LlmModel>>
  _llmModelsRefsTable(_$AppDb db) => MultiTypedResultKey.fromTable(
    db.llmModels,
    aliasName: 'llm_providers__id__llm_models__provider_id',
  );

  $$LlmModelsTableProcessedTableManager get llmModelsRefs {
    final manager = $$LlmModelsTableTableManager(
      $_db,
      $_db.llmModels,
    ).filter((f) => f.providerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_llmModelsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LlmProvidersTableFilterComposer
    extends Composer<_$AppDb, $LlmProvidersTable> {
  $$LlmProvidersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preset => $composableBuilder(
    column: $table.preset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extraJson => $composableBuilder(
    column: $table.extraJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> llmModelsRefs(
    Expression<bool> Function($$LlmModelsTableFilterComposer f) f,
  ) {
    final $$LlmModelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.llmModels,
      getReferencedColumn: (t) => t.providerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LlmModelsTableFilterComposer(
            $db: $db,
            $table: $db.llmModels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LlmProvidersTableOrderingComposer
    extends Composer<_$AppDb, $LlmProvidersTable> {
  $$LlmProvidersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preset => $composableBuilder(
    column: $table.preset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extraJson => $composableBuilder(
    column: $table.extraJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LlmProvidersTableAnnotationComposer
    extends Composer<_$AppDb, $LlmProvidersTable> {
  $$LlmProvidersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get preset =>
      $composableBuilder(column: $table.preset, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get extraJson =>
      $composableBuilder(column: $table.extraJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> llmModelsRefs<T extends Object>(
    Expression<T> Function($$LlmModelsTableAnnotationComposer a) f,
  ) {
    final $$LlmModelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.llmModels,
      getReferencedColumn: (t) => t.providerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LlmModelsTableAnnotationComposer(
            $db: $db,
            $table: $db.llmModels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LlmProvidersTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LlmProvidersTable,
          LlmProvider,
          $$LlmProvidersTableFilterComposer,
          $$LlmProvidersTableOrderingComposer,
          $$LlmProvidersTableAnnotationComposer,
          $$LlmProvidersTableCreateCompanionBuilder,
          $$LlmProvidersTableUpdateCompanionBuilder,
          (LlmProvider, $$LlmProvidersTableReferences),
          LlmProvider,
          PrefetchHooks Function({bool llmModelsRefs})
        > {
  $$LlmProvidersTableTableManager(_$AppDb db, $LlmProvidersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LlmProvidersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LlmProvidersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LlmProvidersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String?> preset = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> extraJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LlmProvidersCompanion(
                id: id,
                kind: kind,
                name: name,
                baseUrl: baseUrl,
                preset: preset,
                enabled: enabled,
                extraJson: extraJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String name,
                required String baseUrl,
                Value<String?> preset = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> extraJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LlmProvidersCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                baseUrl: baseUrl,
                preset: preset,
                enabled: enabled,
                extraJson: extraJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LlmProvidersTable, LlmProvider>(table),
                  $$LlmProvidersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({llmModelsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (llmModelsRefs) db.llmModels],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (llmModelsRefs)
                    await $_getPrefetchedData<
                      LlmProvider,
                      $LlmProvidersTable,
                      LlmModel
                    >(
                      currentTable: table,
                      referencedTable: $$LlmProvidersTableReferences
                          ._llmModelsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LlmProvidersTableReferences(
                            db,
                            table,
                            p0,
                          ).llmModelsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.providerId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LlmProvidersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LlmProvidersTable,
      LlmProvider,
      $$LlmProvidersTableFilterComposer,
      $$LlmProvidersTableOrderingComposer,
      $$LlmProvidersTableAnnotationComposer,
      $$LlmProvidersTableCreateCompanionBuilder,
      $$LlmProvidersTableUpdateCompanionBuilder,
      (LlmProvider, $$LlmProvidersTableReferences),
      LlmProvider,
      PrefetchHooks Function({bool llmModelsRefs})
    >;
typedef $$LlmModelsTableCreateCompanionBuilder =
    LlmModelsCompanion Function({
      required String id,
      required String providerId,
      required String modelId,
      required String displayName,
      Value<String> capsJson,
      Value<String> overridesJson,
      Value<bool> hidden,
      Value<bool> favorite,
      Value<int> rowid,
    });
typedef $$LlmModelsTableUpdateCompanionBuilder =
    LlmModelsCompanion Function({
      Value<String> id,
      Value<String> providerId,
      Value<String> modelId,
      Value<String> displayName,
      Value<String> capsJson,
      Value<String> overridesJson,
      Value<bool> hidden,
      Value<bool> favorite,
      Value<int> rowid,
    });

final class $$LlmModelsTableReferences
    extends BaseReferences<_$AppDb, $LlmModelsTable, LlmModel> {
  $$LlmModelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LlmProvidersTable _providerIdTable(_$AppDb db) =>
      db.llmProviders.createAlias('llm_models__provider_id__llm_providers__id');

  $$LlmProvidersTableProcessedTableManager get providerId {
    final $_column = $_itemColumn<String>('provider_id')!;

    final manager = $$LlmProvidersTableTableManager(
      $_db,
      $_db.llmProviders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_providerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LlmModelsTableFilterComposer
    extends Composer<_$AppDb, $LlmModelsTable> {
  $$LlmModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capsJson => $composableBuilder(
    column: $table.capsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overridesJson => $composableBuilder(
    column: $table.overridesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  $$LlmProvidersTableFilterComposer get providerId {
    final $$LlmProvidersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.providerId,
      referencedTable: $db.llmProviders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LlmProvidersTableFilterComposer(
            $db: $db,
            $table: $db.llmProviders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LlmModelsTableOrderingComposer
    extends Composer<_$AppDb, $LlmModelsTable> {
  $$LlmModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capsJson => $composableBuilder(
    column: $table.capsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overridesJson => $composableBuilder(
    column: $table.overridesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  $$LlmProvidersTableOrderingComposer get providerId {
    final $$LlmProvidersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.providerId,
      referencedTable: $db.llmProviders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LlmProvidersTableOrderingComposer(
            $db: $db,
            $table: $db.llmProviders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LlmModelsTableAnnotationComposer
    extends Composer<_$AppDb, $LlmModelsTable> {
  $$LlmModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capsJson =>
      $composableBuilder(column: $table.capsJson, builder: (column) => column);

  GeneratedColumn<String> get overridesJson => $composableBuilder(
    column: $table.overridesJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  $$LlmProvidersTableAnnotationComposer get providerId {
    final $$LlmProvidersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.providerId,
      referencedTable: $db.llmProviders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LlmProvidersTableAnnotationComposer(
            $db: $db,
            $table: $db.llmProviders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LlmModelsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $LlmModelsTable,
          LlmModel,
          $$LlmModelsTableFilterComposer,
          $$LlmModelsTableOrderingComposer,
          $$LlmModelsTableAnnotationComposer,
          $$LlmModelsTableCreateCompanionBuilder,
          $$LlmModelsTableUpdateCompanionBuilder,
          (LlmModel, $$LlmModelsTableReferences),
          LlmModel,
          PrefetchHooks Function({bool providerId})
        > {
  $$LlmModelsTableTableManager(_$AppDb db, $LlmModelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LlmModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LlmModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LlmModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> providerId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> capsJson = const Value.absent(),
                Value<String> overridesJson = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LlmModelsCompanion(
                id: id,
                providerId: providerId,
                modelId: modelId,
                displayName: displayName,
                capsJson: capsJson,
                overridesJson: overridesJson,
                hidden: hidden,
                favorite: favorite,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String providerId,
                required String modelId,
                required String displayName,
                Value<String> capsJson = const Value.absent(),
                Value<String> overridesJson = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LlmModelsCompanion.insert(
                id: id,
                providerId: providerId,
                modelId: modelId,
                displayName: displayName,
                capsJson: capsJson,
                overridesJson: overridesJson,
                hidden: hidden,
                favorite: favorite,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LlmModelsTable, LlmModel>(table),
                  $$LlmModelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({providerId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (providerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.providerId,
                                referencedTable: $$LlmModelsTableReferences
                                    ._providerIdTable(db),
                                referencedColumn: $$LlmModelsTableReferences
                                    ._providerIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LlmModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $LlmModelsTable,
      LlmModel,
      $$LlmModelsTableFilterComposer,
      $$LlmModelsTableOrderingComposer,
      $$LlmModelsTableAnnotationComposer,
      $$LlmModelsTableCreateCompanionBuilder,
      $$LlmModelsTableUpdateCompanionBuilder,
      (LlmModel, $$LlmModelsTableReferences),
      LlmModel,
      PrefetchHooks Function({bool providerId})
    >;
typedef $$McpServersTableCreateCompanionBuilder =
    McpServersCompanion Function({
      required String id,
      required String name,
      Value<String> transport,
      required String url,
      Value<bool> enabled,
      Value<String> toolsCacheJson,
      Value<String> disabledToolsJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$McpServersTableUpdateCompanionBuilder =
    McpServersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> transport,
      Value<String> url,
      Value<bool> enabled,
      Value<String> toolsCacheJson,
      Value<String> disabledToolsJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$McpServersTableFilterComposer
    extends Composer<_$AppDb, $McpServersTable> {
  $$McpServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transport => $composableBuilder(
    column: $table.transport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolsCacheJson => $composableBuilder(
    column: $table.toolsCacheJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get disabledToolsJson => $composableBuilder(
    column: $table.disabledToolsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$McpServersTableOrderingComposer
    extends Composer<_$AppDb, $McpServersTable> {
  $$McpServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transport => $composableBuilder(
    column: $table.transport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolsCacheJson => $composableBuilder(
    column: $table.toolsCacheJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get disabledToolsJson => $composableBuilder(
    column: $table.disabledToolsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$McpServersTableAnnotationComposer
    extends Composer<_$AppDb, $McpServersTable> {
  $$McpServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get transport =>
      $composableBuilder(column: $table.transport, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get toolsCacheJson => $composableBuilder(
    column: $table.toolsCacheJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get disabledToolsJson => $composableBuilder(
    column: $table.disabledToolsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$McpServersTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $McpServersTable,
          McpServer,
          $$McpServersTableFilterComposer,
          $$McpServersTableOrderingComposer,
          $$McpServersTableAnnotationComposer,
          $$McpServersTableCreateCompanionBuilder,
          $$McpServersTableUpdateCompanionBuilder,
          (McpServer, BaseReferences<_$AppDb, $McpServersTable, McpServer>),
          McpServer,
          PrefetchHooks Function()
        > {
  $$McpServersTableTableManager(_$AppDb db, $McpServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$McpServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$McpServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$McpServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> transport = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> toolsCacheJson = const Value.absent(),
                Value<String> disabledToolsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpServersCompanion(
                id: id,
                name: name,
                transport: transport,
                url: url,
                enabled: enabled,
                toolsCacheJson: toolsCacheJson,
                disabledToolsJson: disabledToolsJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> transport = const Value.absent(),
                required String url,
                Value<bool> enabled = const Value.absent(),
                Value<String> toolsCacheJson = const Value.absent(),
                Value<String> disabledToolsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => McpServersCompanion.insert(
                id: id,
                name: name,
                transport: transport,
                url: url,
                enabled: enabled,
                toolsCacheJson: toolsCacheJson,
                disabledToolsJson: disabledToolsJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$McpServersTable, McpServer>(table),
                  BaseReferences<_$AppDb, $McpServersTable, McpServer>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$McpServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $McpServersTable,
      McpServer,
      $$McpServersTableFilterComposer,
      $$McpServersTableOrderingComposer,
      $$McpServersTableAnnotationComposer,
      $$McpServersTableCreateCompanionBuilder,
      $$McpServersTableUpdateCompanionBuilder,
      (McpServer, BaseReferences<_$AppDb, $McpServersTable, McpServer>),
      McpServer,
      PrefetchHooks Function()
    >;
typedef $$SkillsTableCreateCompanionBuilder =
    SkillsCompanion Function({
      required String id,
      required String name,
      required String description,
      required String body,
      Value<String> source,
      Value<String?> dir,
      Value<bool> enabled,
      Value<DateTime> installedAt,
      Value<int> rowid,
    });
typedef $$SkillsTableUpdateCompanionBuilder =
    SkillsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> description,
      Value<String> body,
      Value<String> source,
      Value<String?> dir,
      Value<bool> enabled,
      Value<DateTime> installedAt,
      Value<int> rowid,
    });

class $$SkillsTableFilterComposer extends Composer<_$AppDb, $SkillsTable> {
  $$SkillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dir => $composableBuilder(
    column: $table.dir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SkillsTableOrderingComposer extends Composer<_$AppDb, $SkillsTable> {
  $$SkillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dir => $composableBuilder(
    column: $table.dir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SkillsTableAnnotationComposer extends Composer<_$AppDb, $SkillsTable> {
  $$SkillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get dir =>
      $composableBuilder(column: $table.dir, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );
}

class $$SkillsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $SkillsTable,
          Skill,
          $$SkillsTableFilterComposer,
          $$SkillsTableOrderingComposer,
          $$SkillsTableAnnotationComposer,
          $$SkillsTableCreateCompanionBuilder,
          $$SkillsTableUpdateCompanionBuilder,
          (Skill, BaseReferences<_$AppDb, $SkillsTable, Skill>),
          Skill,
          PrefetchHooks Function()
        > {
  $$SkillsTableTableManager(_$AppDb db, $SkillsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SkillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SkillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> dir = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillsCompanion(
                id: id,
                name: name,
                description: description,
                body: body,
                source: source,
                dir: dir,
                enabled: enabled,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String description,
                required String body,
                Value<String> source = const Value.absent(),
                Value<String?> dir = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillsCompanion.insert(
                id: id,
                name: name,
                description: description,
                body: body,
                source: source,
                dir: dir,
                enabled: enabled,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SkillsTable, Skill>(table),
                  BaseReferences<_$AppDb, $SkillsTable, Skill>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SkillsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $SkillsTable,
      Skill,
      $$SkillsTableFilterComposer,
      $$SkillsTableOrderingComposer,
      $$SkillsTableAnnotationComposer,
      $$SkillsTableCreateCompanionBuilder,
      $$SkillsTableUpdateCompanionBuilder,
      (Skill, BaseReferences<_$AppDb, $SkillsTable, Skill>),
      Skill,
      PrefetchHooks Function()
    >;
typedef $$NasDevicesTableCreateCompanionBuilder =
    NasDevicesCompanion Function({
      required String id,
      required String name,
      required String baseUrl,
      Value<String> infoJson,
      Value<bool> isDefault,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });
typedef $$NasDevicesTableUpdateCompanionBuilder =
    NasDevicesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> baseUrl,
      Value<String> infoJson,
      Value<bool> isDefault,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });

class $$NasDevicesTableFilterComposer
    extends Composer<_$AppDb, $NasDevicesTable> {
  $$NasDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get infoJson => $composableBuilder(
    column: $table.infoJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NasDevicesTableOrderingComposer
    extends Composer<_$AppDb, $NasDevicesTable> {
  $$NasDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get infoJson => $composableBuilder(
    column: $table.infoJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NasDevicesTableAnnotationComposer
    extends Composer<_$AppDb, $NasDevicesTable> {
  $$NasDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get infoJson =>
      $composableBuilder(column: $table.infoJson, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);
}

class $$NasDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $NasDevicesTable,
          NasDevice,
          $$NasDevicesTableFilterComposer,
          $$NasDevicesTableOrderingComposer,
          $$NasDevicesTableAnnotationComposer,
          $$NasDevicesTableCreateCompanionBuilder,
          $$NasDevicesTableUpdateCompanionBuilder,
          (NasDevice, BaseReferences<_$AppDb, $NasDevicesTable, NasDevice>),
          NasDevice,
          PrefetchHooks Function()
        > {
  $$NasDevicesTableTableManager(_$AppDb db, $NasDevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NasDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NasDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NasDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> infoJson = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NasDevicesCompanion(
                id: id,
                name: name,
                baseUrl: baseUrl,
                infoJson: infoJson,
                isDefault: isDefault,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String baseUrl,
                Value<String> infoJson = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NasDevicesCompanion.insert(
                id: id,
                name: name,
                baseUrl: baseUrl,
                infoJson: infoJson,
                isDefault: isDefault,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NasDevicesTable, NasDevice>(table),
                  BaseReferences<_$AppDb, $NasDevicesTable, NasDevice>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NasDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $NasDevicesTable,
      NasDevice,
      $$NasDevicesTableFilterComposer,
      $$NasDevicesTableOrderingComposer,
      $$NasDevicesTableAnnotationComposer,
      $$NasDevicesTableCreateCompanionBuilder,
      $$NasDevicesTableUpdateCompanionBuilder,
      (NasDevice, BaseReferences<_$AppDb, $NasDevicesTable, NasDevice>),
      NasDevice,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer extends Composer<_$AppDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDb, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDb, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDb, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$ChatsTableTableManager get chats =>
      $$ChatsTableTableManager(_db, _db.chats);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$MemoriesTableTableManager get memories =>
      $$MemoriesTableTableManager(_db, _db.memories);
  $$LlmProvidersTableTableManager get llmProviders =>
      $$LlmProvidersTableTableManager(_db, _db.llmProviders);
  $$LlmModelsTableTableManager get llmModels =>
      $$LlmModelsTableTableManager(_db, _db.llmModels);
  $$McpServersTableTableManager get mcpServers =>
      $$McpServersTableTableManager(_db, _db.mcpServers);
  $$SkillsTableTableManager get skills =>
      $$SkillsTableTableManager(_db, _db.skills);
  $$NasDevicesTableTableManager get nasDevices =>
      $$NasDevicesTableTableManager(_db, _db.nasDevices);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
