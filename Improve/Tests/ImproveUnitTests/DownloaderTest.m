//
//  DownloaderTest.m
//  ImproveUnitTests
//
//  Created by Vladimir on 2/10/20.
//  Copyright © 2020 Mind Blown Apps, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "IMPModelDownloader.h"
#import "TestUtils.h"

@interface DownloaderTest : XCTestCase

@end

@interface IMPModelDownloader ()

- (NSURL *)modelsDirURL;

- (BOOL)compileModelAtURL:(NSURL *)modelDefinitionURL
                    toURL:(NSURL *)destURL
                    error:(NSError **)error;

@end

@implementation DownloaderTest

- (void)testCompile {
    // Insert url for local or remote .mlmodel file here
    NSURL *modelDefinitionURL = [NSURL fileURLWithPath:@"/Users/vk/Dev/_PROJECTS_/ImproveAI-SKLearnObjC/test models/29May/model.mlmodel"];
    NSURL *compiledURL = [NSURL fileURLWithPath:@"/Users/vk/Dev/_PROJECTS_/ImproveAI-SKLearnObjC/test models/29May/model.mlmodelc"];
    XCTAssertNotNil(modelDefinitionURL);

    // Url isn't used here.
    NSURL *dummyURL = [NSURL fileURLWithPath:@""];
    IMPModelDownloader *downloader = [[IMPModelDownloader alloc] initWithURL:dummyURL];

    for (NSUInteger i = 0; i < 3; i++) // Loop to check overwriting.
    {
        NSError *err;
        if (![downloader compileModelAtURL:modelDefinitionURL
                                     toURL:compiledURL
                                     error:&err])
        {
            NSLog(@"Compilation error: %@", err);
        }
        XCTAssertNotNil(compiledURL);
        NSLog(@"%@", compiledURL);
    }
    if ([[NSFileManager defaultManager] removeItemAtURL:compiledURL error:nil]) {
        NSLog(@"Deleted.");
    }
}

- (void)testDownload {
    // Insert url for local or remote archive here
    //NSURL *remoteURL = [NSURL URLWithString:@"https://d2pq40dxlsc486.cloudfront.net/myproject/model.tar.gz"];
    NSURL *url = [NSURL fileURLWithPath:@"/Users/vk/Dev/_PROJECTS_/ImproveAI-SKLearnObjC/test models/multimodels/mlmodels/latest.tar.gz"];
    IMPModelDownloader *downloader = [[IMPModelDownloader alloc] initWithURL:url];

    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Model downloaded"];
    [downloader loadWithCompletion:^(NSArray *modelBundles, NSError *error) {
        if (error != nil) {
            XCTFail(@"Downloading error: %@", error);
        }
        XCTAssert(modelBundles.count > 0);
        NSLog(@"Model bundle: %@", modelBundles);

        // Cleenup
//        NSURL *folderURL = bundle.modelURL.URLByDeletingLastPathComponent;
//        if ([[NSFileManager defaultManager] removeItemAtURL:folderURL error:nil]) {
//            NSLog(@"Deleted.");
//        }

        [expectation fulfill];
    }];

    [self waitForExpectations:@[expectation] timeout:60.0];
}

- (void)testCache {
    NSURL *url = [NSURL fileURLWithPath:@"/Users/vk/Dev/_PROJECTS_/ImproveAI-SKLearnObjC/test models/multimodels/mlmodels/latest.tar.gz"];
    IMPModelDownloader *downloader = [[IMPModelDownloader alloc] initWithURL: url];

    // Clean before tests
    [[NSFileManager defaultManager] removeItemAtURL:[downloader modelsDirURL] error:nil];

    XCTAssert(downloader.cachedModelBundles.count == 0);

    NSTimeInterval age = [downloader cachedModelsAge];
    XCTAssert(age == DBL_MAX);

    XCTestExpectation *expectation = [[XCTestExpectation alloc] init];
    NSTimeInterval cacheAgeSeconds = 10.0;
    [downloader loadWithCompletion:^(NSArray *modelBundles, NSError *error) {
        XCTAssertNotNil(downloader.cachedModelBundles);
        XCTAssert(downloader.cachedModelBundles.count == modelBundles.count);

        NSTimeInterval age = downloader.cachedModelsAge;
        NSLog(@"After download cachedModelsAge: %f", age);
        XCTAssert(isEqualRough(age, 0.0, 0.1));

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(cacheAgeSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSTimeInterval age = [downloader cachedModelsAge];
            NSLog(@"After %fs cachedModelsAge: %f", cacheAgeSeconds, age);
            XCTAssert(isEqualRough(age, cacheAgeSeconds, 0.1));
            [expectation fulfill];
        });
    }];

    [self waitForExpectations:@[expectation] timeout:cacheAgeSeconds + 30.0];
}

@end
