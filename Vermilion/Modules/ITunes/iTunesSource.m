//
//  iTunesSource.m
//
//  Copyright (c) 2008 Google Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//    * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the
//  distribution.
//    * Neither the name of Google Inc. nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

// TODO(hawk): Clean up this file so that it complies with the 
//             coding guidelines. Please don't just wrap the lines,
//             instead break them up so that they are easy to parse and debug.

#import "iTunesSource.h"
#import "GTMSQLite.h"
#import "GTMGarbageCollection.h"
#import "HGSAbbreviationRanker.h"
#import "HGSTokenizer.h"

NSString *const kITunesAttributeTrackIdKey = @"kITunesAttributeTrackIdKey";
NSString *const kITunesAttributeArtistKey = @"kITunesAttributeArtistKey";
NSString *const kITunesAttributeAlbumKey = @"kITunesAttributeAlbumKey";
NSString *const kITunesAttributeComposerKey = @"kITunesAttributeComposerKey";
NSString *const kITunesAttributeGenreKey = @"kITunesAttributeGenreKey";
NSString *const kITunesAttributeIconFileKey = @"kITunesAttributeIconFileKey";
NSString *const kITunesAttributePlaylistKey = @"kITunesAttributePlaylistKey";
NSString *const kITunesAttributePlaylistIdKey = @"kITunesAttributePlaylistIdKey";

static const CGFloat kGenreMatchAdjustment = -0.2;
static const NSUInteger kMaxSearchResults = 100;
static const NSTimeInterval kInitialIndexDelay = 10; // 10 seconds
static const NSTimeInterval kUpdateTimeInterval = 600; // 10 minutes
static const NSInteger kInsertsPerTransaction = 100;
static const NSStringCompareOptions kResultStringCompareOptions 
  = NSCaseInsensitiveSearch 
  | NSDiacriticInsensitiveSearch 
  | NSWidthInsensitiveSearch;
static NSString* const kITunesXmlPath 
  = @"~/Music/iTunes/iTunes Music Library.xml";
static NSString* const kTracksKey = @"Tracks";
static NSString* const kPlaylistsKey = @"Playlists";
static NSString* const kSqlCreateStatement =
  @"CREATE TABLE 'tracks' ("
   "  'trackid' INTEGER,"
   "  'name' TEXT COLLATE NOCASE_NONLITERAL_NODIACRITIC_WIDTHINSENSITIVE,"
   "  'artist' TEXT COLLATE NOCASE_NONLITERAL_NODIACRITIC_WIDTHINSENSITIVE,"
   "  'album' TEXT COLLATE NOCASE_NONLITERAL_NODIACRITIC_WIDTHINSENSITIVE,"
   "  'composer' TEXT COLLATE NOCASE_NONLITERAL_NODIACRITIC_WIDTHINSENSITIVE,"
   "  'genre' TEXT NOCASE_NONLITERAL_NODIACRITIC_WIDTHINSENSITIVE,"
   "  'location' TEXT"
   ");"
   "CREATE TABLE 'playlists' ("
   "  'playlistid' INTEGER,"
   "  'name' TEXT NOCASE_NONLITERAL_NODIACRITIC_WIDTHINSENSITIVE"
   ");"
   "CREATE TABLE 'playlist_tracks' ("
   "  'playlistid' INTEGER,"
   "  'trackid' INTEGER"
   ");"
   "CREATE INDEX trackid_index ON tracks (trackid);"
   "CREATE INDEX name_index ON tracks (name);"
   "CREATE INDEX artist_index ON tracks (artist);"
   "CREATE INDEX album_index ON tracks (album);"
   "CREATE INDEX composer_index ON tracks (composer);"
   "CREATE INDEX genre_index ON tracks (genre);"
   "CREATE INDEX playlist_index ON playlists (name);";
static NSString* const kTrackInsertSql 
  = @"INSERT INTO tracks VALUES (%i,%@,%@,%@,%@,%@,%@);\n";
static NSString* const kPlaylistInsertSql 
  = @"INSERT INTO playlists VALUES (%i,%@);\n";
static NSString* const kPlaylistTrackInsertSql 
  = @"INSERT INTO playlist_tracks VALUES (%i,%i);\n";
static NSString* const kSqlSelectStatement =
  @"SELECT * FROM tracks WHERE "
   "name LIKE %@ OR "
   "artist LIKE %@ OR "
   "album LIKE %@ OR "
   "composer LIKE %@ OR "
   "genre LIKE %@;";
static NSString* const kPlaylistSelectStatement 
  = @"SELECT * FROM playlists WHERE name LIKE %@;";
static NSString* const kPlaylistFromTrackSelectStatement =
  @"SELECT * FROM playlists WHERE playlistid IN (SELECT playlistid from "
  @"playlist_tracks WHERE trackid=%i);";
static NSString* const kTracksFromAlbumSelectStatement =
  @"SELECT * FROM tracks WHERE album=%@;";
static NSString* const kTracksFromPlaylistSelectStatement =
  @"SELECT * FROM tracks WHERE trackid IN (SELECT trackid FROM playlist_tracks "
  @"WHERE playlistid=%i);";
static NSString* const kPivotFromArtistSelectStatement =
  @"SELECT DISTINCT album,artist,composer,genre,location FROM tracks WHERE "
  @"artist=%@;";
static NSString* const kPivotFromComposerSelectStatement =
  @"SELECT DISTINCT album,artist,composer,genre,location FROM tracks WHERE "
  @"composer=%@;";
static NSString* const kPivotFromGenreSelectStatement =
  @"SELECT DISTINCT album,artist,composer,genre,location FROM tracks WHERE "
  @"genre=%@;";
static NSString* const kArtistUrlFormat = @"googletunes://artist/%@";
static NSString* const kAlbumUrlFormat = @"googletunes://album/%@";
static NSString* const kComposerUrlFormat = @"googletunes://composer/%@";
static NSString* const kGenreUrlFormat = @"googletunes://genre/%@";
static NSString* const kPlaylistUrlFormat = @"googletunes://playlist/%@";

@class ITunesPlayAction;

@interface ITunesSource : HGSCallbackSearchSource {
 @private
  GTMSQLiteDatabase *db_;
  __weak NSTimer *updateTimer_;
  // TODO(hawk): Should these all go in the icon cache?
  NSImage *albumIcon_;
  NSImage *artistIcon_;
  NSImage *composerIcon_;
  NSImage *genreIcon_;
  NSImage *playlistIcon_;
  BOOL indexing_;
  NSMutableDictionary *genreIconCache_;
}

- (void)updateIndex;
- (void)updateIndexTimerFired:(NSTimer *)timer;
- (GTMSQLiteDatabase *)createDatabase;
- (void)performPivotOperation:(HGSSearchOperation*)operation
               forTrackObject:(HGSResult *)pivotObject;
- (void)performPivotOperation:(HGSSearchOperation*)operation
               forAlbumObject:(HGSResult *)pivotObject
                    withQuery:(NSString *)query ;
- (void)performPivotOperation:(HGSSearchOperation*)operation
            forPlaylistObject:(HGSResult *)pivotObject
                    withQuery:(NSString *)query;
- (void)performPivotOperation:(HGSSearchOperation*)operation
                    forObject:(HGSResult *)pivotObject
                    withQuery:(NSString *)query;
- (HGSResult *)trackResult:(NSString *)track
           withTrackNumber:(int)trackNumber
                   onAlbum:(NSString *)album
                  byArtist:(NSString *)artist
                byComposer:(NSString *)composer
                   inGenre:(NSString *)genre
                atLocation:(NSString *)location
                playListID:(NSString *)playListID
                 matchedBy:(NSString *)queryString;
- (HGSResult *)albumResult:(NSString *)album
                  byArtist:(NSString *)artist
                byComposer:(NSString *)composer
                   inGenre:(NSString *)genre
              withIconFile:(NSString *)iconFilePath
                 matchedBy:(NSString *)queryString;
- (HGSResult *)artistResult:(NSString *)artist
                  matchedBy:(NSString *)queryString;
- (HGSResult *)composerResult:(NSString *)composer
                    matchedBy:(NSString *)queryString;
- (HGSResult *)genreResult:(NSString *)genre
                 matchedBy:(NSString *)queryString;
- (HGSResult *)playListResult:(NSString *)playlist
                   playlistId:(NSString *)playlistId
                    matchedBy:(NSString *)queryString;
- (CGFloat)rankForString:(NSString *)string matchedBy:(NSString *)queryString;
- (HGSAction *)defaultAction;
- (NSImage *)iconForGenre:(NSString *)genre;
@end

@implementation ITunesSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {    
    // Create the initial in-memory database
    db_ = [[self createDatabase] retain];
    NSBundle *bundle = HGSGetPluginBundle();
    // Preload our placeholder icons
    NSString *path = [bundle pathForResource:@"iTunesAlbumBrowserIcon"
                                    ofType:@"png"];
    albumIcon_= [[NSImage alloc] initByReferencingFile:path];
    
    path = [bundle pathForResource:@"iTunesArtistBrowserIcon"
                            ofType:@"png"];
    artistIcon_= [[NSImage alloc] initByReferencingFile:path];

    path = [bundle pathForResource:@"iTunesComposerBrowserIcon"
                            ofType:@"png"];
    composerIcon_= [[NSImage alloc] initByReferencingFile:path];
    
    path = [bundle pathForResource:@"iTunesGenreBrowserIcon"
                            ofType:@"png"];
    genreIcon_= [[NSImage alloc] initByReferencingFile:path];
    
    path = [bundle pathForResource:@"iTunesPlaylistIcon"
                            ofType:@"icns"];
    playlistIcon_= [[NSImage alloc] initByReferencingFile:path];
    
    // Periodically update the index
    updateTimer_ 
      = [NSTimer scheduledTimerWithTimeInterval:kUpdateTimeInterval
                                         target:self
                                       selector:@selector(updateIndexTimerFired:)
                                       userInfo:nil
                                        repeats:YES];
    
    genreIconCache_ = [[NSMutableDictionary alloc] init];

    HGSAssert(db_, nil);
    HGSAssert(albumIcon_, nil);
    HGSAssert(artistIcon_, nil);
    HGSAssert(composerIcon_, nil);
    HGSAssert(genreIcon_, nil);
    HGSAssert(playlistIcon_, nil);
    HGSAssert(updateTimer_, nil);
    HGSAssert(genreIconCache_, nil);
    
    // Perform the first index of the iTunes library after a small delay
    // to avoid the synchronous hit at startup time
    [self performSelector:@selector(updateIndexTimerFired:)
               withObject:nil
               afterDelay:kInitialIndexDelay];
  }
  return self;
}

- (void)dealloc {
  [updateTimer_ invalidate];
  [db_ release];
  [albumIcon_ release];
  [artistIcon_ release];
  [composerIcon_ release];
  [genreIcon_ release];
  [playlistIcon_ release];
  [genreIconCache_ release];
  [super dealloc];
}

- (NSString *)libraryLocation {
  NSArray *paths
    = GTMCFAutorelease(CFPreferencesCopyAppValue(CFSTR("iTunesRecentDatabasePaths"),
                                                 CFSTR("com.apple.iApps")));
  
  NSString *libraryLocation = [paths count] ? [paths objectAtIndex:0] : nil;
  if (!libraryLocation) {
    libraryLocation = kITunesXmlPath;
  }
  
  return [libraryLocation stringByExpandingTildeInPath];
}

- (void)updateIndex {
  GTMSQLiteDatabase *db = nil;
  
  // Only one indexing operation at a time
  @synchronized (updateTimer_) {
    if (indexing_) {
      return;
    }
    indexing_ = YES;
    
    // 
    NSString *pathToITunesXml = [self libraryLocation];
    NSDictionary *rootDictionary 
      = [NSDictionary dictionaryWithContentsOfFile:pathToITunesXml];
    if (!rootDictionary) {
      HGSLogDebug(@"iTunes source failed to parse %@", pathToITunesXml);
      indexing_ = NO;
      return;
    }
    
    // Create the sqlite in-memory database that we'll use to store iTunes data
    db = [self createDatabase];
    
    // Insert the tracks into database using chunked transactions; this
    // increases the sqlite insert speed by an order of magnitude. Perform
    // the inserts in chunks so we don't exhaust memory
    int sqliteErr;
    NSArray *tracks = [rootDictionary objectForKey:kTracksKey];
    NSInteger trackCount = [tracks count];
    NSEnumerator *trackEnumerator = [tracks objectEnumerator];
    for (NSInteger chunkIteration = 0; chunkIteration < trackCount;) {
      NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];
      NSString *trackSql = @"BEGIN TRANSACTION;\n";
      for (NSInteger trackIteration = 0;
           trackIteration < kInsertsPerTransaction 
             && chunkIteration < trackCount;
           trackIteration++, chunkIteration++) {
        NSDictionary *track = [trackEnumerator nextObject];
        NSString *trackName = [track objectForKey:@"Name"];
        if (trackName) {
          trackName = [GTMSQLiteStatement quoteAndEscapeString:trackName];
        }
        NSString *trackArtist = [track objectForKey:@"Artist"];
        if (trackArtist) {
          trackArtist = [GTMSQLiteStatement quoteAndEscapeString:trackArtist];
        }
        NSString *trackAlbum = [track objectForKey:@"Album"];
        if (trackAlbum) {
          trackAlbum = [GTMSQLiteStatement quoteAndEscapeString:trackAlbum];
        }
        NSString *trackComposer = [track objectForKey:@"Composer"];
        if (trackComposer) {
          trackComposer 
            = [GTMSQLiteStatement quoteAndEscapeString:trackComposer];
        }
        NSString *trackGenre = [track objectForKey:@"Genre"];
        if (trackGenre) {
          trackGenre = [GTMSQLiteStatement quoteAndEscapeString:trackGenre];
        }
        NSString *trackLocation = [track objectForKey:@"Location"];
        if (trackLocation) {
          trackLocation 
            = [GTMSQLiteStatement quoteAndEscapeString:trackLocation];
        }
        trackSql = [trackSql stringByAppendingFormat:kTrackInsertSql,
                    [[track objectForKey:@"Track ID"] intValue],
                    trackName ? trackName : @"''",
                    trackArtist ? trackArtist : @"''",
                    trackAlbum ? trackAlbum : @"''",
                    trackComposer ? trackComposer : @"''",
                    trackGenre ? trackGenre : @"''",
                    trackLocation ? trackLocation : @"''"];
      }
      trackSql = [trackSql stringByAppendingString:@"COMMIT;\n"];
      if ((sqliteErr = [db executeSQL:trackSql]) != SQLITE_OK) {
        HGSLog(@"iTunes source could not insert track info into its database "
               @"(%i, %@)", sqliteErr, [db lastErrorString]);
        HGSLogDebug(@"%@", trackSql);
      }
      [loopPool release];
    }
    NSArray *playlists = [rootDictionary objectForKey:kPlaylistsKey];
    for (NSDictionary *playlist in playlists) {
      if ([[playlist objectForKey:@"Master"] boolValue]) {
        // Don't index the master playlist, it's a rehash of everything we've
        // already indexed above
        continue;
      }
      NSInteger playlistId = [[playlist objectForKey:@"Playlist ID"] intValue];
      NSString *playlistName = [playlist objectForKey:@"Name"];
      playlistName = [GTMSQLiteStatement quoteAndEscapeString:playlistName];
      NSString *playlistSql  = [NSString stringWithFormat:kPlaylistInsertSql,
                                playlistId,
                                playlistName ? playlistName : @"''"];
      if ((sqliteErr = [db executeSQL:playlistSql]) != SQLITE_OK) {
        HGSLog(@"iTunes source could not insert playlist info into its "
               @"database (%i, %@)", sqliteErr, [db lastErrorString]);
        HGSLogDebug(@"%@", playlistSql);
      }
      NSArray *playlistItems = [playlist objectForKey:@"Playlist Items"];
      trackCount = [playlistItems count];
      trackEnumerator = [playlistItems objectEnumerator];
      for (NSInteger chunkIteration = 0; chunkIteration < trackCount;) {
        NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];
        NSString *playlistTrackSql = @"BEGIN TRANSACTION;\n";
        for (NSInteger trackIteration = 0;
             trackIteration < kInsertsPerTransaction
               && chunkIteration < trackCount;
             trackIteration++, chunkIteration++) {
          NSDictionary *track = [trackEnumerator nextObject];
          playlistTrackSql 
            = [playlistTrackSql stringByAppendingFormat:kPlaylistTrackInsertSql,
               playlistId, [[track objectForKey:@"Track ID"] intValue]];
        }
        playlistTrackSql 
          = [playlistTrackSql stringByAppendingString:@"COMMIT;\n"];
        if ((sqliteErr = [db executeSQL:playlistTrackSql]) != SQLITE_OK) {
          HGSLog(@"iTunes source could not insert playlist track info into "
                 @"its database (%i, %@)", sqliteErr, [db lastErrorString]);
          HGSLogDebug(@"%@", playlistTrackSql);
        }
        [loopPool release];
      }
    }
    
    indexing_ = NO;
  }
  
  // Swap the newly indexed database with the previous one
  @synchronized (self) {
    if (db) {
      [db_ release];
      db_ = [db retain];
    }
  }
}

- (void)updateIndexTimerFired:(NSTimer *)timer {
  NSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(updateIndex)
                              object:nil]];
}

- (GTMSQLiteDatabase *)createDatabase {
  int sqliteErr;
  GTMSQLiteDatabase *db 
    = [[[GTMSQLiteDatabase alloc] initInMemoryWithCFAdditions:YES
                                                         utf8:YES
                                                    errorCode:&sqliteErr] 
       autorelease];
  if (!db || (sqliteErr = [db executeSQL:kSqlCreateStatement]) != SQLITE_OK) {
    HGSLog(@"iTunes source could not create its database (%i, %@)",
           sqliteErr, [db lastErrorString]);
    return nil;
  }
  [db setLikeComparisonOptions:(kCFCompareCaseInsensitive | 
                                kCFCompareNonliteral |
                                kCFCompareDiacriticInsensitive |
                                kCFCompareWidthInsensitive)];
  return db;
}

- (void)performPivotOperation:(HGSSearchOperation*)operation
               forTrackObject:(HGSResult *)pivotObject {
  // For tracks, return the artist, composer, genre, and the album
  // on which the track appears 
  NSMutableArray *results = [NSMutableArray array];
  NSString *artist = [pivotObject valueForKey:kITunesAttributeArtistKey];
  NSString *album = [pivotObject valueForKey:kITunesAttributeAlbumKey];
  NSString *composer = [pivotObject valueForKey:kITunesAttributeComposerKey];
  NSString *genre = [pivotObject valueForKey:kITunesAttributeGenreKey];
  
  if ([artist length]) {
    [results addObject:[self artistResult:artist matchedBy:nil]];
  }
  
  if ([album length]) {
    NSString *path = [pivotObject filePath];
    HGSResult *newAlbum = [self albumResult:album
                                   byArtist:artist
                                 byComposer:composer
                                    inGenre:genre
                               withIconFile:path
                                  matchedBy:nil];
    [results addObject:newAlbum];
  }
  
  if ([composer length]) {
    [results addObject:[self composerResult:composer matchedBy:nil]];
  }
  
  if ([genre length]) {
    [results addObject:[self genreResult:genre matchedBy:nil]];
  }
  
  // Add all playlists to which the track belongs
  NSNumber *trackID = [pivotObject valueForKey:kITunesAttributeTrackIdKey];
  NSString *sqlSelect 
    = [NSString stringWithFormat:kPlaylistFromTrackSelectStatement,
       [trackID intValue]];
  @synchronized (self) {
    int sqliteErr;
    GTMSQLiteStatement *statement 
      = [GTMSQLiteStatement statementWithSQL:sqlSelect
                                  inDatabase:db_
                                   errorCode:&sqliteErr];
    if (statement && !sqliteErr) {
      while ([statement stepRow] == SQLITE_ROW) {
        if ([operation isCancelled]) {
          break;
        }
        NSString *playlistId = [statement resultStringAtPosition:0];
        NSString *playlist = [statement resultStringAtPosition:1];
        [results addObject:[self playListResult:playlist
                                     playlistId:playlistId
                                      matchedBy:nil]];
      }
    }
    [statement finalizeStatement];
  }
  
  [operation setResults:results];
}

- (void)performPivotOperation:(HGSSearchOperation*)operation
               forAlbumObject:(HGSResult *)pivotObject
                    withQuery:(NSString *)query  {
  // For albums, return tracks from the album
  NSString *pivotObjectAlbum 
    = [pivotObject valueForKey:kITunesAttributeAlbumKey];
  pivotObjectAlbum = [GTMSQLiteStatement quoteAndEscapeString:pivotObjectAlbum];
  NSString *sqlSelect 
    = [NSString stringWithFormat:kTracksFromAlbumSelectStatement, 
       pivotObjectAlbum];
  @synchronized (self) {
    int sqliteErr;
    GTMSQLiteStatement *statement 
      = [GTMSQLiteStatement statementWithSQL:sqlSelect
                                  inDatabase:db_
                                   errorCode:&sqliteErr];
    NSMutableArray *results = [NSMutableArray array];
    if (statement && !sqliteErr) {
      while ([statement stepRow] == SQLITE_ROW) {
        if ([operation isCancelled]) {
          break;
        }
        NSString *track = [statement resultStringAtPosition:1];
        if (![query length] 
            || [track rangeOfString:query
                            options:kResultStringCompareOptions].location 
            != NSNotFound) {
          int trackId = [[statement resultStringAtPosition:0] intValue];
          NSString *artist = [statement resultStringAtPosition:2];
          NSString *album = [statement resultStringAtPosition:3];
          NSString *composer = [statement resultStringAtPosition:4];
          NSString *genre = [statement resultStringAtPosition:5];
          NSString *location = [statement resultStringAtPosition:6];
          [results addObject:[self trackResult:track
                               withTrackNumber:trackId
                                       onAlbum:album
                                      byArtist:artist
                                    byComposer:composer
                                       inGenre:genre
                                    atLocation:location
                                    playListID:nil
                                     matchedBy:query]];
        }
      }
    }
    [operation setResults:results];
    [statement finalizeStatement];
  }
}

- (void)performPivotOperation:(HGSSearchOperation*)operation
            forPlaylistObject:(HGSResult *)pivotObject
                    withQuery:(NSString *)query {
  // For playlists, return tracks from the playlist
  NSInteger pivotObjectPlaylistId 
    = [[pivotObject valueForKey:kITunesAttributePlaylistIdKey] intValue];
  NSString *sqlSelect 
    = [NSString stringWithFormat:kTracksFromPlaylistSelectStatement,
       pivotObjectPlaylistId];
  @synchronized (self) {
    int sqliteErr;
    GTMSQLiteStatement *statement 
      = [GTMSQLiteStatement statementWithSQL:sqlSelect
                                  inDatabase:db_
                                   errorCode:&sqliteErr];
    NSMutableArray *results = [NSMutableArray array];
    if (statement && !sqliteErr) {
      while ([statement stepRow] == SQLITE_ROW) {
        if ([operation isCancelled]) {
          break;
        }
        NSString *track = [statement resultStringAtPosition:1];
        if (![query length] 
            || [track rangeOfString:query
                            options:kResultStringCompareOptions].location 
            != NSNotFound) {
          int trackId = [[statement resultStringAtPosition:0] intValue];
          NSString *artist = [statement resultStringAtPosition:2];
          NSString *album = [statement resultStringAtPosition:3];
          NSString *composer = [statement resultStringAtPosition:4];
          NSString *genre = [statement resultStringAtPosition:5];
          NSString *location = [statement resultStringAtPosition:6];
          NSString *playListID 
            = [pivotObject valueForKey:kITunesAttributePlaylistIdKey];
          HGSResult *result =  [self trackResult:track
                                 withTrackNumber:trackId
                                         onAlbum:album
                                        byArtist:artist
                                      byComposer:composer
                                         inGenre:genre
                                      atLocation:location
                                        playListID:playListID
                                       matchedBy:query];
          [results addObject:result];
        }
      }
    }
    [operation setResults:results];
    [statement finalizeStatement];
  }
}

- (void)performPivotOperation:(HGSSearchOperation*)operation
                    forObject:(HGSResult *)pivotObject
                    withQuery:(NSString *)query {
  NSString *sqlSelect = nil;
  if ([pivotObject isOfType:kTypeITunesArtist]) {
    // For artists, return albums by the artist
    NSString *artist = [pivotObject valueForKey:kITunesAttributeArtistKey];
    artist = [GTMSQLiteStatement quoteAndEscapeString:artist];
    sqlSelect = [NSString stringWithFormat:kPivotFromArtistSelectStatement,
                 artist];
  } else if ([pivotObject isOfType:kTypeITunesComposer]) {
    // For composers, return albums by the composer
    NSString *composer = [pivotObject valueForKey:kITunesAttributeComposerKey];
    composer = [GTMSQLiteStatement quoteAndEscapeString:composer];
    sqlSelect = [NSString stringWithFormat:kPivotFromComposerSelectStatement,
                 composer];
  } else {
    // For genres, return albums belonging to the genre
    NSString *genre = [pivotObject valueForKey:kITunesAttributeGenreKey];
    genre = [GTMSQLiteStatement quoteAndEscapeString:genre];
    sqlSelect = [NSString stringWithFormat:kPivotFromGenreSelectStatement,
                 genre];
  }
  
  @synchronized (self) {
    // Synchronized because sqlite allows only single thread access to an 
    // in-memory db
    int sqliteErr;
    GTMSQLiteStatement *statement
      = [GTMSQLiteStatement statementWithSQL:sqlSelect
                                  inDatabase:db_
                                   errorCode:&sqliteErr];
    NSMutableArray *results = [NSMutableArray array];
    if (statement && !sqliteErr) {
      while ([statement stepRow] == SQLITE_ROW 
             && [results count] < kMaxSearchResults) {
        if ([operation isCancelled]) {
          break;
        }
        NSString *album = [statement resultStringAtPosition:0];
        if (![query length] 
            || [album rangeOfString:query
                            options:kResultStringCompareOptions].location 
            != NSNotFound) {
          NSString *artist = [statement resultStringAtPosition:1];
          NSString *composer = [statement resultStringAtPosition:2];
          NSString *genre = [statement resultStringAtPosition:3];
          NSString *location = [statement resultStringAtPosition:4];
          [results addObject:[self albumResult:album
                                      byArtist:artist
                                    byComposer:composer
                                       inGenre:genre
                                  withIconFile:location
                                     matchedBy:query]];
        }
      }
    }
    [operation setResults:results];
    [statement finalizeStatement];
  }
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSString *sqlSelect = nil;
  // TODO(hawk): we should probably revisit a fair amount of this to better
  // handle more then one query term:
  //   -- in the like line below, handle the terms in any order, etc. (like
  //      the spotlight source does).
  //   -- in the helpers for pivots, handle multiple terms w/o doing matches
  //      in the middle of words (ie-segment), maybe also match all parts of
  //      a track instead of just single parts of the track metadata.
  NSString *query = [[operation query] rawQueryString];
  HGSResult *pivotObject = [[operation query] pivotObject];
  if (pivotObject) {
    if ([pivotObject isOfType:kTypeITunesTrack]) {
      [self performPivotOperation:operation forTrackObject:pivotObject];
    } else if ([pivotObject isOfType:kTypeITunesAlbum]) {
      [self performPivotOperation:operation 
                   forAlbumObject:pivotObject 
                        withQuery:query];
    } else if ([pivotObject isOfType:kTypeITunesPlaylist]) {
      [self performPivotOperation:operation 
                forPlaylistObject:pivotObject 
                        withQuery:query];
    } else if ([pivotObject isOfType:kTypeITunesArtist] ||
               [pivotObject isOfType:kTypeITunesComposer] ||
               [pivotObject isOfType:kTypeITunesGenre]) {
      [self performPivotOperation:operation
                        forObject:pivotObject
                        withQuery:query];
    }
  } else {
    NSString *likeString = [NSString stringWithFormat:@"%%%@%%", query];
    likeString = [GTMSQLiteStatement quoteAndEscapeString:likeString];
    sqlSelect = [NSString stringWithFormat:kSqlSelectStatement,
                 likeString, likeString, likeString, likeString, likeString];
    NSMutableSet *results = [NSMutableSet set];
    @synchronized (self) {
      // Synchronized because sqlite allows only single thread access to an 
      // in-memory db
      int sqliteErr;
      GTMSQLiteStatement *statement 
        = [GTMSQLiteStatement statementWithSQL:sqlSelect
                                    inDatabase:db_
                                     errorCode:&sqliteErr];
      if (statement && !sqliteErr) {
        while ([statement stepRow] == SQLITE_ROW 
               && [results count] < kMaxSearchResults) {
          if ([operation isCancelled]) {
            break;
          }
          NSString *track = [statement resultStringAtPosition:1];
          NSString *artist = [statement resultStringAtPosition:2];
          NSString *album = [statement resultStringAtPosition:3];
          NSString *composer = [statement resultStringAtPosition:4];
          NSString *genre = [statement resultStringAtPosition:5];
          NSString *location = [statement resultStringAtPosition:6];
          
          // We matched at least one column, figure out which column(s) matched
          // and create an appropriate result object for it
          if ([track rangeOfString:query 
                           options:kResultStringCompareOptions].location 
              != NSNotFound) {
            // Track name matched
            int trackNumber = [[statement resultStringAtPosition:0] intValue];
            [results addObject:[self trackResult:track
                                 withTrackNumber:trackNumber
                                         onAlbum:album
                                        byArtist:artist
                                      byComposer:composer
                                         inGenre:genre
                                      atLocation:location
                                      playListID:nil
                                       matchedBy:query]];
          }
          NSRange range = [artist rangeOfString:query 
                                        options:kResultStringCompareOptions];
          if (range.location != NSNotFound) {
            // Artist matched
            [results addObject:[self artistResult:artist matchedBy:query]];
          }
          range = [album rangeOfString:query 
                               options:kResultStringCompareOptions];
          if (range.location != NSNotFound) {
            // Album matched
            [results addObject:[self albumResult:album
                                        byArtist:artist
                                      byComposer:composer
                                         inGenre:genre
                                   withIconFile:location
                                       matchedBy:query]];
          }
          range = [composer rangeOfString:query 
                                  options:kResultStringCompareOptions];
          if (range.location != NSNotFound) {
            // Composer matched
            [results addObject:[self composerResult:composer matchedBy:query]];
          }
          range = [genre rangeOfString:query 
                               options:kResultStringCompareOptions];
          if (range.location != NSNotFound) {
            // Genre matched
            [results addObject:[self genreResult:genre matchedBy:query]];
          }
        }
      }
      
      if (sqliteErr) {
          HGSLog(@"iTunes source could not select from its database (%i, %@)",
                 sqliteErr, [db_ lastErrorString]);
      }
      [statement finalizeStatement];
      
      likeString = [NSString stringWithFormat:@"%%%@%%", query];
      likeString = [GTMSQLiteStatement quoteAndEscapeString:likeString];
      sqlSelect = [NSString stringWithFormat:kPlaylistSelectStatement, 
                   likeString];
      statement = [GTMSQLiteStatement statementWithSQL:sqlSelect
                                            inDatabase:db_
                                             errorCode:&sqliteErr];
      if (statement && !sqliteErr) {
        while ([statement stepRow] == SQLITE_ROW) {
          if ([operation isCancelled]) {
            break;
          }
          NSString *playlistId = [statement resultStringAtPosition:0];
          NSString *playlist = [statement resultStringAtPosition:1];
          [results addObject:[self playListResult:playlist
                                       playlistId:playlistId
                                        matchedBy:query]];
        }
      }
      
      [statement finalizeStatement];
    }
    
    [operation setResults:[results allObjects]];
  }
}

- (NSMutableDictionary *)archiveRepresentationForResult:(HGSResult*)result {
  // Don't want itunes results remembered in shortcuts
  // TODO(hawk): revisit when we don't use a subclass and see if we can save a 
  // few things to rebuild the real result.
  return nil;
}

- (HGSResult *)resultWithArchivedRepresentation:(NSDictionary *)representation {
  // Don't want itunes results remembered in shortcuts
  // TODO(hawk): revisit when we don't use a subclass and see if we can save a 
  // few things to rebuild the real result.
  return nil;
}

- (HGSResult *)trackResult:(NSString *)track
           withTrackNumber:(int)trackNumber
                   onAlbum:(NSString *)album
                  byArtist:(NSString *)artist
                byComposer:(NSString *)composer
                   inGenre:(NSString *)genre
                atLocation:(NSString *)location 
                playListID:(NSString *)playListID
                 matchedBy:(NSString *)queryString {
  CGFloat rank = [self rankForString:track matchedBy:queryString];
  NSMutableDictionary *attributes 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       [NSNumber numberWithInt:trackNumber], kITunesAttributeTrackIdKey,
       [NSNumber numberWithDouble:rank], kHGSObjectAttributeRankKey,
       [self defaultAction], kHGSObjectAttributeDefaultActionKey,
       nil];
  NSInteger artistLength = [artist length], albumLength = [album length];
  if (albumLength && artistLength) {
    [attributes setObject:[NSString stringWithFormat:@"%@ - %@", album, artist] 
              forKey:kHGSObjectAttributeSnippetKey];
  } else if (albumLength) {
    [attributes setObject:album forKey:kHGSObjectAttributeSnippetKey];
  } else if (artistLength) {
    [attributes setObject:artist forKey:kHGSObjectAttributeSnippetKey];
  }
  if (albumLength) {
    [attributes setObject:album forKey:kITunesAttributeAlbumKey];
  }
  if (artistLength) {
    [attributes setObject:artist forKey:kITunesAttributeArtistKey];
  }
  if ([composer length]) {
    [attributes setObject:composer forKey:kITunesAttributeComposerKey];
  }
  if ([genre length]) {
    [attributes setObject:genre forKey:kITunesAttributeGenreKey];
  }
  if ([playListID length]) {
    [attributes setObject:playListID forKey:kITunesAttributePlaylistIdKey];
  }
  
  return [HGSResult resultWithURI:location
                             name:track
                             type:kTypeITunesTrack
                           source:self
                       attributes:attributes];
}

- (HGSResult *)albumResult:(NSString *)album
                  byArtist:(NSString *)artist
                byComposer:(NSString *)composer
                   inGenre:(NSString *)genre
              withIconFile:(NSString *)iconFilePath
                 matchedBy:(NSString *)queryString {
  NSString *albumUrlString 
    = [NSString stringWithFormat:kAlbumUrlFormat,
       [album stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  CGFloat rank = [self rankForString:album matchedBy:queryString];
  NSMutableDictionary *attributes 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       [self defaultAction], kHGSObjectAttributeDefaultActionKey,
       [NSURL fileURLWithPath:iconFilePath], kHGSObjectAttributeIconPreviewFileKey,
       [NSNumber numberWithDouble:rank], kHGSObjectAttributeRankKey,
       albumIcon_, kHGSObjectAttributeIconKey,
       nil];
  if ([artist length]) {
    [attributes setObject:artist forKey:kHGSObjectAttributeSnippetKey];
    [attributes setObject:artist forKey:kITunesAttributeArtistKey];
  }
  if ([album length]) {
    [attributes setObject:album forKey:kITunesAttributeAlbumKey];
  }
  if ([composer length]) {
    [attributes setObject:composer forKey:kITunesAttributeComposerKey];
  }
  if ([genre length]) {
    [attributes setObject:genre forKey:kITunesAttributeGenreKey];
  }
  
  return [HGSResult resultWithURI:albumUrlString
                             name:album
                             type:kTypeITunesAlbum
                           source:self
                       attributes:attributes];
}

- (HGSResult *)artistResult:(NSString *)artist 
                  matchedBy:(NSString *)queryString {
  NSString *artistUrlString 
    = [NSString stringWithFormat:kArtistUrlFormat,
       [artist stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  HGSAction *action = [self defaultAction];
  CGFloat rank = [self rankForString:artist matchedBy:queryString];
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       artist, kITunesAttributeArtistKey,
       artistIcon_, kHGSObjectAttributeIconKey,
       action, kHGSObjectAttributeDefaultActionKey,
       [NSNumber numberWithDouble:rank], kHGSObjectAttributeRankKey,
       nil];
  return [HGSResult resultWithURI:artistUrlString
                             name:artist
                             type:kTypeITunesArtist
                           source:self
                       attributes:attributes];
}

- (HGSResult *)composerResult:(NSString *)composer
                    matchedBy:(NSString *)queryString {
  NSString *composerUrlString 
    = [NSString stringWithFormat:kComposerUrlFormat,
       [composer stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  HGSAction *action = [self defaultAction];
  CGFloat rank = [self rankForString:composer matchedBy:queryString];
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       composer, kITunesAttributeComposerKey,
       composerIcon_, kHGSObjectAttributeIconKey,
       action, kHGSObjectAttributeDefaultActionKey,
       [NSNumber numberWithDouble:rank], kHGSObjectAttributeRankKey,
       nil];
  return [HGSResult resultWithURI:composerUrlString
                             name:composer
                             type:kTypeITunesComposer
                           source:self
                       attributes:attributes];
}

- (NSImage *)iconForGenre:(NSString *)genre {
  NSImage *icon = nil;
  @synchronized(genreIconCache_) {
    icon = [genreIconCache_ objectForKey:genre];
    if (!icon) {
      // Attempt to find a more specific icon representing the genre in the
      // iTunes app bundle. If not found, fall back on the generic icon
      NSWorkspace *ws = [NSWorkspace sharedWorkspace];
      NSString *iTunesPath
        = [ws absolutePathForAppBundleWithIdentifier:@"com.apple.iTunes"];
      NSBundle *iTunesBundle = [NSBundle bundleWithPath:iTunesPath];
      NSString *imageName
        = [NSString stringWithFormat:@"genre-%@", [genre lowercaseString]];
      NSString *imagePath = [iTunesBundle pathForImageResource:imageName];
      if (imagePath) {
        icon = [[[NSImage alloc] initByReferencingFile:imagePath] autorelease];
      }
      if (!icon) {
        icon = genreIcon_;
      } 
      [genreIconCache_ setObject:icon forKey:genre];
    }
  }
  return icon;
}

- (HGSResult *)genreResult:(NSString *)genre
                 matchedBy:(NSString *)queryString {
  NSString *genreUrlString 
    = [NSString stringWithFormat:kGenreUrlFormat,
       [genre stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  
  NSImage *icon = [self iconForGenre:genre];
  CGFloat rank = [self rankForString:genre 
                           matchedBy:queryString] + kGenreMatchAdjustment;
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       genre, kITunesAttributeGenreKey,
       icon, kHGSObjectAttributeIconKey, 
       [self defaultAction], kHGSObjectAttributeDefaultActionKey,
       [NSNumber numberWithDouble:rank], kHGSObjectAttributeRankKey,
       nil];
  return [HGSResult resultWithURI:genreUrlString
                             name:genre
                             type:kTypeITunesGenre
                           source:self
                       attributes:attributes];
}

- (HGSResult *)playListResult:(NSString *)playlist
                   playlistId:(NSString *)playlistId
                    matchedBy:(NSString *)queryString {
  NSString *playlistUrlString 
    = [NSString stringWithFormat:kPlaylistUrlFormat,
       [playlist stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  CGFloat rank = [self rankForString:playlist matchedBy:queryString];
  NSDictionary *attributes
    = [NSDictionary dictionaryWithObjectsAndKeys:
       playlistId, kITunesAttributePlaylistIdKey,
       playlist, kITunesAttributePlaylistKey,
       playlistIcon_, kHGSObjectAttributeIconKey,
       [self defaultAction], kHGSObjectAttributeDefaultActionKey,
       [NSNumber numberWithDouble:rank], kHGSObjectAttributeRankKey,
       nil];
  return [HGSResult resultWithURI:playlistUrlString
                             name:playlist
                             type:kTypeITunesPlaylist
                           source:self
                       attributes:attributes];
}

- (HGSAction *)defaultAction {
  NSString *actionName = 
    @"com.google.qsb.itunes.action.play";
  HGSAction *action 
    = [[HGSExtensionPoint actionsPoint] extensionWithIdentifier:actionName];
  if (!action) {
    HGSLog(@"Unable to get default play action for iTunes (%@)", actionName);
  }
  return action;
}

- (CGFloat)rankForString:(NSString *)string matchedBy:(NSString *)queryString {
  CGFloat rank = 0;
  if (string && queryString) {
    string = [HGSTokenizer tokenizeString:string];
    queryString = [HGSTokenizer tokenizeString:queryString];
    rank = HGSScoreForAbbreviation(string, queryString, NULL);
  }
  return rank;
}

@end
