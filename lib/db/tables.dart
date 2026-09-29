// The eight tables (§5.2). Nothing sensitive lives here: the JWT is in secure storage only.
import 'package:drift/drift.dart';

@TableIndex(name: 'media_files_moviehash', columns: {#moviehash})
@DataClassName('MediaRow')
class MediaFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get locator => text().unique()();
  TextColumn get displayName => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get moviehash => text().nullable()();
  TextColumn get origin => text().withDefault(const Constant('localPath'))();
  TextColumn get title => text().nullable()(); // identified feature title, for the marquee
  IntColumn get year => integer().nullable()();
  TextColumn get container => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  RealColumn get fps => real().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get videoCodec => text().nullable()();
  TextColumn get audioCodec => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
}

/// The ticket-saver. Consulted before any network call on every open.
@DataClassName('HashCacheRow')
class HashCache extends Table {
  TextColumn get moviehash => text()();
  TextColumn get language => text()();
  TextColumn get provider => text()();
  TextColumn get fileId => text().nullable()();
  TextColumn get release => text().nullable()();
  TextColumn get sidecarPath => text()();
  BoolColumn get syncedByHash => boolean()();
  BoolColumn get besideFile => boolean().withDefault(const Constant(true))();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {moviehash, language};
}

@DataClassName('ResumeRow')
class ResumePoints extends Table {
  TextColumn get moviehash => text()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {moviehash};
}

@DataClassName('OffsetRow')
class SyncOffsets extends Table {
  TextColumn get moviehash => text()();
  IntColumn get delayMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {moviehash};
}

@DataClassName('FolderRow')
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get locator => text().unique()();
  TextColumn get grantBlob => text().nullable()();
  DateTimeColumn get lastScanAt => dateTime().nullable()();
}

@TableIndex(name: 'artwork_expires_at', columns: {#expiresAt})
@DataClassName('ArtworkRow')
class Artwork extends Table {
  IntColumn get tmdbId => integer()();
  TextColumn get posterPath => text().nullable()();
  TextColumn get backdropPath => text().nullable()();
  IntColumn get accentArgb => integer().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {tmdbId};
}

/// 24 h TTL on search responses only; the download cache (the sidecar) never expires.
@DataClassName('SearchCacheRow')
class SearchCache extends Table {
  TextColumn get queryKey => text()();
  TextColumn get bodyJson => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {queryKey};
}

/// Keys: settings, window_bounds, seen_gate_nudge. No shared_preferences.
@DataClassName('AppStateRow')
class AppState extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
