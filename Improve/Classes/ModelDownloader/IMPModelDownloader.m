//
//  IMPModelDownloader.m
//  ImproveUnitTests
//
//  Created by Vladimir on 2/8/20.
//  Copyright © 2020 Mind Blown Apps, LLC. All rights reserved.
//

#import "IMPModelDownloader.h"
#import <CoreML/CoreML.h>
#import "NSFileManager+SafeCopy.h"
#import "IMPLogging.h"

// https://github.com/nvh/NVHTarGzip
// We can add pod dependency if the author will fix bug with `gzFile` pointers.
// See issue: https://github.com/nvh/NVHTarGzip/pull/24
#import "NVHTarGzip.h"

/**
 The folder in Library/Caches directory. Contains subfolders where individual downloaders store
 the cached files. Each subfolder is associated with the corresponding remoteArchiveURL.
 Subfolders contain compiled models file - .mlmodelc and metadata - .json.

 Library/Caches/RootFolder
 - subfoldr1
 -- modelname1.mlmodelc
 -- modelname1.json
 -- modelname2.mlmodelc
 -- modelname2.json
 - subfoldr2
 -- modelname3.mlmodelc
 -- modelname3.json
 */
NSString *const kModelsRootFolderName = @"ai.improve.models";

@implementation IMPModelDownloader {
    /// User Defaults contain NSString - folder name.
    NSString *_userDefaultsFolderKey;

    /// Key for NSDate object - date when the archive was sucesfully downloaded.
    NSString *_userDefaultsLastDownloadDateKey;

    /**
     Random folder name which is associated with the archive URL and stored in User Defaults.
     Cached models for that URL will be stored in this folder.
     */
    NSString *_folderName;

    NSURLSessionDataTask *_downloadTask;

    NSFileManager *_fileManager;
}

- (instancetype)initWithURL:(NSURL *)remoteArchiveURL
{
    self = [super init];
    if (self) {
        _remoteArchiveURL = [remoteArchiveURL copy];
        _fileManager = [NSFileManager defaultManager];

        _userDefaultsFolderKey = [NSString stringWithFormat:@"ai.improve.modelDirectory.%@", remoteArchiveURL.absoluteString];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _folderName = [defaults stringForKey:_userDefaultsFolderKey];
        if (!_folderName) {
            _folderName = [[NSUUID UUID] UUIDString];
            IMPLog("Folder name created.");
            [defaults setObject:_folderName forKey:_userDefaultsFolderKey];
        }
        IMPLog("Cache folder name: %@", _folderName);

        _userDefaultsLastDownloadDateKey = [NSString stringWithFormat:@"ai.improve.lastDownloadDate.%@", remoteArchiveURL.absoluteString];
    }
    return self;
}

- (NSURL *)modelsDirURL
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSURL *cachesDir = [fileManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    if (!cachesDir) {
        IMPErrLog("Failed to get system caches directory: %@", error);
    }
    NSURL *url = [cachesDir URLByAppendingPathComponent:kModelsRootFolderName];
    url = [cachesDir URLByAppendingPathComponent:_folderName];

    // Ensure existance
    if (![url checkResourceIsReachableAndReturnError:nil]) {
        if(![fileManager createDirectoryAtURL:url
                  withIntermediateDirectories:true
                                   attributes:nil
                                        error:nil]) {
            IMPErrLog("Failed to create models directory: %@", error);
        }
    }

    return url;
}

- (NSArray *)cachedModelFileURLs {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSArray *fileURLs = [fileManager contentsOfDirectoryAtURL:self.modelsDirURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error];
    if (!fileURLs) {
        IMPErrLog("Directory enumeration error: %@", error);
    }
    return fileURLs;
}

- (nullable NSArray *)cachedModelBundles
{
    IMPLog("Retrieving cached models...");
    NSArray *fileURLs = [self cachedModelFileURLs];
    if (!fileURLs) {
        IMPLog("Failed to get cached file urls.");
        return nil;
    }
    IMPLog("File urls: %@", fileURLs);

    NSMutableArray *bundles = [NSMutableArray new];
    for (NSURL *url in fileURLs)
    {
        NSString *extension = url.pathExtension;
        NSString *name = url.lastPathComponent.stringByDeletingPathExtension;

        if (![extension isEqualToString:@"json"]) {
            continue;
        }

        IMPModelBundle *bundle = [[IMPModelBundle alloc] initWithDirectoryURL:self.modelsDirURL modelName:name];

        // Check if all files for the givent model name exists
        if (bundle.isReachable) {
            IMPLog("Bundle is unreachable: %@", bundle);
            [bundles addObject:bundle];
        }
    }

    IMPLog("Retrieved cached bunles: %@", bundles);
    return bundles;
}

- (NSTimeInterval)cachedModelsAge {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *fileURLs = [self cachedModelFileURLs];
    if (!fileURLs || fileURLs.count == 0) {
        // No files - no cached models yet or cache was purged
        [defaults removeObjectForKey:_userDefaultsLastDownloadDateKey];
        return DBL_MAX;
    }

    NSDate *lastDownloadDate = [defaults objectForKey:_userDefaultsLastDownloadDateKey];
    if (!lastDownloadDate) {
        return DBL_MAX;
    }

    NSTimeInterval age = -[lastDownloadDate timeIntervalSinceNow];
    return age;
}

- (void)loadWithCompletion:(IMPModelDownloaderCompletion)completion
{
    IMPLog("Loading models at: %@", self.remoteArchiveURL);
    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.remoteArchiveURL];
    [request setHTTPMethod:@"GET"];
    [request setAllHTTPHeaderFields:self.headers];
    // Disable the built-in cache, because we rely on the custom one.
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    _downloadTask = [session dataTaskWithRequest:request
                           completionHandler:
                     ^(NSData * _Nullable data,
                       NSURLResponse * _Nullable response,
                       NSError * _Nullable downloadingError) {
        if (!data) {
            IMPLog("Finish loading - no data; response: %@, error: %@", response, downloadingError);
            if (completion) { completion(nil, downloadingError); }
            return;
        }

        NSError *error; // General purpose error

        // Optional check for HTTP responses, will not be called for file URLs
        if ([response isKindOfClass:NSHTTPURLResponse.class])
        {
            // Perform additional check to exit early and prevent further errors.
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResponse.statusCode;
            if (statusCode != 200) {
                NSString *statusCodeStr = [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
                NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSString *msg = [NSString stringWithFormat:@"Model loading failed with status code: %ld %@. Data: %@. URL: %@", statusCode, statusCodeStr, dataStr, response.URL];
                error = [NSError errorWithDomain:@"ai.improve.IMPModelDownloader"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: msg}];
                IMPLog("Loading failed: %@", error);
                if (completion) { completion(nil, error); }
                return;
            }
        }

        IMPLog("Loaded %ld bytes.", data.length);

        // Save downloaded archive
        NSString *tempDir = NSTemporaryDirectory();
        NSString *archiveDir = [tempDir stringByAppendingPathComponent:@"ai.improve.tmp/"];
        IMPLog("Creating directory for the downloaded achive: %@ ...", archiveDir);
        NSError *dirError;
        if (![self->_fileManager createDirectoryAtPath:archiveDir
                     withIntermediateDirectories:true
                                      attributes:nil
                                           error:&dirError])
        {
            NSString *errMsg = [NSString stringWithFormat:@"Failed to create directory for archive: %@, Src URL: %@", archiveDir, self.remoteArchiveURL];

            error = [NSError errorWithDomain:@"ai.improve.IMPModelDownloader"
                                        code:-100
                                    userInfo:@{NSLocalizedDescriptionKey: errMsg,
                                               NSUnderlyingErrorKey: dirError}];
            IMPLog("Directory creation failed: %@", errMsg);
            if (completion) { completion(nil, error); }
            return;
        }
        IMPLog("Success.");

        NSString *archivePath = [archiveDir stringByAppendingPathComponent:@"models.tar.gz"];
        IMPLog("Writing the archive data to path: %@ ...", archivePath);
        if (![data writeToFile:archivePath atomically:YES]) {
            NSString *errMsg = [NSString stringWithFormat:@"Failed to write received data to file. Src URL: %@, Dest path: %@ Size: %ld", self.remoteArchiveURL, archivePath, data.length];
            error = [NSError errorWithDomain:@"ai.improve.IMPModelDownloader"
                                        code:-100
                                    userInfo:@{NSLocalizedDescriptionKey: errMsg}];
            IMPLog("Failed: %@", errMsg);
            if (completion) { completion(nil, error); }
            return;
        }
        IMPLog("Success.");

        // Unarchiving
        NSString *unarchivePath = [tempDir stringByAppendingPathComponent:@"ai.improve.tmp/Unarchived Models"];
        IMPLog("Untarin the archive to path: %@ ...", unarchivePath);
        if (![[NVHTarGzip sharedInstance] unTarGzipFileAtPath:archivePath
                                                       toPath:unarchivePath
                                                        error:&error])
        {
            IMPLog("Untar failed: %@", error);
            if (completion) { completion(nil, error); }
            return;
        }
        IMPLog("Success.");

        NSArray *bundles = [self processUnarchivedModelFilesIn:unarchivePath
                                                         error:&error];
        if (!bundles) {
            if (completion) { completion(nil, error); }
        }
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date]
                                                  forKey:self->_userDefaultsLastDownloadDateKey];
        IMPLog("Model downloaded finished. Returning bundles: %@", bundles);
        if (completion) { completion(bundles, nil); }
    }];
    [_downloadTask resume];
}

- (void)cancel
{
    [_downloadTask cancel];
}

- (BOOL)compileModelAtURL:(NSURL *)modelDefinitionURL
                    toURL:(NSURL *)destURL
                    error:(NSError **)error
{
    if (![_fileManager fileExistsAtPath:modelDefinitionURL.path]) {
        NSString *msg = [NSString stringWithFormat:@"Model definition not found at local path: %@. Remove URL: %@", modelDefinitionURL.path, self.remoteArchiveURL];
        *error = [NSError errorWithDomain:@"ai.improve.compile_model"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: msg}];
        return false;
    }

    NSURL *compiledURL = [MLModel compileModelAtURL:modelDefinitionURL error:error];
    if (!compiledURL) return false;

    if (![_fileManager safeCopyItemAtURL:compiledURL toURL:destURL error:error]) {
        return false;
    }
    return true;
}

- (BOOL)isLoading {
    return _downloadTask && _downloadTask.state != NSURLSessionTaskStateRunning;
}

- (NSArray<IMPModelBundle *> * _Nullable)processUnarchivedModelFilesIn:(NSString *)folder
                                                                 error:(NSError **)error
{
    IMPLog("Processing unarchived models in dir: %@", folder);
    NSURL *folderURL = [NSURL fileURLWithPath:folder];

    NSArray *files = [_fileManager contentsOfDirectoryAtURL:folderURL
                                 includingPropertiesForKeys:nil
                                                    options:NSDirectoryEnumerationSkipsHiddenFiles
                                                      error:error];
    if (!files) {
        IMPLog("Failed to get files in the directory: %@", error);
        return nil;
    }
    IMPLog("Contents: %@", files);

    // Filter files
    NSMutableSet *mlmodelNames = [NSMutableSet setWithCapacity:files.count];
    NSMutableSet *jsonNames = [NSMutableSet setWithCapacity:files.count];
    for (NSURL *file in files)
    {
        NSString *extension = file.pathExtension;
        NSString *modelName = file.lastPathComponent.stringByDeletingPathExtension;

        if ([extension isEqualToString:@"mlmodel"]) {
            [mlmodelNames addObject:modelName];
        } else if ([extension isEqualToString:@"json"]) {
            [jsonNames addObject:modelName];
        }
    }
    [mlmodelNames intersectSet:jsonNames];
    IMPLog("Found model names: %@", mlmodelNames);

    // Process models
    NSMutableArray *modelBundles = [NSMutableArray arrayWithCapacity:mlmodelNames.count];
    for (NSString *modelName in mlmodelNames)
    {
        NSString *mlmodelFileName = [NSString stringWithFormat:@"%@.mlmodel", modelName];
        NSString *mlmodelPath = [folder stringByAppendingPathComponent:mlmodelFileName];

        NSString *jsonFileName = [NSString stringWithFormat:@"%@.json", modelName];
        NSString *jsonPath = [folder stringByAppendingPathComponent:jsonFileName];

        IMPModelBundle *bundleOrNil = [self processModelWithName:modelName
                                                        withPath:mlmodelPath
                                                        jsonPath:jsonPath];
        [modelBundles addObject:bundleOrNil];
    }

    IMPLog("Processing unarchived models finished. Bundles: %@", modelBundles);
    return modelBundles;
}

- (IMPModelBundle *)processModelWithName:(NSString *)modelName
                                withPath:(NSString *)mlmodelPath
                                jsonPath:(NSString *)jsonPath
{
    IMPModelBundle *bundle = [[IMPModelBundle alloc] initWithDirectoryURL:self.modelsDirURL modelName:modelName];
    IMPLog("Processing model: %@", modelName);

    // Compile model and put to the destination folder
    NSURL *modelDefinitionURL = [NSURL fileURLWithPath:mlmodelPath];
    NSError *error;
    IMPLog("Compiling model at: %@ to: %@ ...", modelDefinitionURL, bundle.compiledModelURL);
    if (![self compileModelAtURL:modelDefinitionURL
                           toURL:bundle.compiledModelURL
                           error:&error])
    {
        IMPErrLog("Failed to compile model: %@, at: %@ to: %@ error: %@", modelName, modelDefinitionURL, bundle.compiledModelURL, error);
        return nil;
    }
    IMPLog("Success.");

    // Put metadata to the destination folder
    NSURL *metadataURL = [NSURL fileURLWithPath:jsonPath];
    IMPLog("Copying metadata: %@ to: %@ ...", metadataURL, bundle.metadataURL);
    if (![_fileManager safeCopyItemAtURL:metadataURL
                                   toURL:bundle.metadataURL
                                   error:&error])
    {
        IMPErrLog("Failed to copy metadata for model: %@, from: %@ to: %@ error: %@", modelName, metadataURL, bundle.metadataURL, error);
        return nil;
    }
    IMPLog("Success.");

    IMPLog("Returning bundle: %@", bundle);
    return bundle;
}

@end
