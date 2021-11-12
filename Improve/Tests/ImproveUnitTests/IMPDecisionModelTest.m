//
//  DecisionModelTest.m
//  ImproveUnitTests
//
//  Created by PanHongxi on 3/22/21.
//  Copyright © 2021 Mind Blown Apps, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "IMPDecisionModel.h"
#import "IMPDecision.h"
#import "IMPUtils.h"
#import "TestUtils.h"
#import "IMPFeatureEncoder.h"

extern NSString * const kRemoteModelURL;

@interface IMPDecisionModel ()

+ (nullable id)topScoringVariant:(NSArray *)variants withScores:(NSArray <NSNumber *>*)scores;

+ (NSArray *)rank:(NSArray *)variants withScores:(NSArray <NSNumber *>*)scores;

+ (NSArray *)generateDescendingGaussians:(NSUInteger)count;

- (IMPFeatureEncoder *)featureEncoder;

- (BOOL)enableTieBreaker;

- (void)setEnableTieBreaker:(BOOL)enableTieBreaker;

@end

@interface IMPDecisionModelTest : XCTestCase

@property (strong, nonatomic) NSArray *urlList;

@end

@implementation IMPDecisionModelTest

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
    NSLog(@"%@", [[TestUtils bundle] bundlePath]);
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (NSArray *)urlList{
    if(_urlList == nil){
        _urlList = @[
            [NSURL URLWithString:kRemoteModelURL],
            [[TestUtils bundle] URLForResource:@"TestModel"
                                 withExtension:@"mlmodelc"]];
    }
    return _urlList;
}

- (void)testInit {
    IMPDecisionModel *decisionModel = [[IMPDecisionModel alloc] initWithModelName:@"hello"];
    XCTAssertEqualObjects(decisionModel.modelName, @"hello");
}

- (void)testModelName {
    IMPDecisionModel *decisionModel = [[IMPDecisionModel alloc] initWithModelName:@"hello"];
    NSURL *url = [[TestUtils bundle] URLForResource:@"TestModel"
                                      withExtension:@"mlmodelc"];
    XCTestExpectation *ex = [[XCTestExpectation alloc] initWithDescription:@"Waiting for model creation"];
    [decisionModel loadAsync:url completion:^(IMPDecisionModel * _Nullable compiledModel, NSError * _Nullable error) {
        XCTAssertEqualObjects(decisionModel.modelName, @"songs-2.0");
        [ex fulfill];
    }];
    [self waitForExpectations:@[ex] timeout:3];
}

- (void)testLoadLocalModelFile {
    NSError *error;
    NSURL *modelURL = [[TestUtils bundle] URLForResource:@"TestModel"
                         withExtension:@"dat"];
    NSLog(@"model url: %@", modelURL);
    IMPDecisionModel *model = [IMPDecisionModel load:modelURL error:&error];
    XCTAssertNotNil(model);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"songs-2.0", model.modelName);
}

- (void)testLoadAsync{
    for(NSURL *url in self.urlList){
        XCTestExpectation *ex = [[XCTestExpectation alloc] initWithDescription:@"Waiting for model creation"];
        IMPDecisionModel *decisionModel = [[IMPDecisionModel alloc] initWithModelName:@""];
        [decisionModel loadAsync:url completion:^(IMPDecisionModel * _Nullable compiledModel, NSError * _Nullable error) {
            if(error){
                NSLog(@"loadAsync error: %@", error);
            }
            XCTAssert([NSThread isMainThread]);
            XCTAssertNotNil(compiledModel);
            XCTAssertTrue([compiledModel.modelName length] > 0);
            [ex fulfill];
        }];
        [self waitForExpectations:@[ex] timeout:300];
    }
}

- (void)testLoadSync {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    NSError *err;
    for(NSURL *url in self.urlList){
        IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:&err];
        XCTAssertNil(err);
        XCTAssertNotNil(decisionModel);
        XCTAssertTrue([decisionModel.modelName length] > 0);
    }
}

- (void)testLoadSyncToFail {
    NSError *err;
    NSURL *url = [NSURL URLWithString:@"http://192.168.1.101/not/exist/TestModel.mlmodel3.gz"];
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:&err];
    XCTAssertNotNil(err);
    XCTAssertNil(decisionModel);
}

- (void)testLoadSyncToFailWithInvalidModelFile {
    NSError *err;
    // The model exists, but is not valid
    NSURL *modelURL = [[TestUtils bundle] URLForResource:@"InvalidModel"
                         withExtension:@"dat"];
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:modelURL error:&err];
    XCTAssertNotNil(err);
    XCTAssertNil(decisionModel);
    NSLog(@"load error: %@", err);
}

- (void)testLoadSyncFromNonMainThread{
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    
    XCTestExpectation *ex = [[XCTestExpectation alloc] initWithDescription:@"Waiting for model creation"];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        XCTAssert(![NSThread isMainThread]);
        NSError *err;
        for(NSURL *url in self.urlList){
            NSLog(@"model: %@", url);
            IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:&err];
            XCTAssertNil(err);
            XCTAssertNotNil(decisionModel);
            XCTAssertTrue([decisionModel.modelName length] > 0);
        }
        NSURL *url = [NSURL URLWithString:kRemoteModelURL];
        IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:&err];
        [decisionModel chooseFrom:@[]];
        [ex fulfill];
    });
    [self waitForExpectations:@[ex] timeout:300];
}

- (void)testDescendingGaussians {
    int n = 40000;
    double total = 0.0;
    
    NSArray *array = [IMPDecisionModel generateDescendingGaussians:n];
    XCTAssertEqual(array.count, n);
    
    for(int i = 0; i < n; ++i) {
        total += [[array objectAtIndex:i] doubleValue];
    }
    
    NSLog(@"median = %f, average = %f", [[array objectAtIndex:n/2] doubleValue], total / n);
    XCTAssertLessThan(ABS([[array objectAtIndex:n/2] doubleValue]), 0.05);
    
    // Test that it it descending
    for(int i = 0; i < n-1; ++i) {
        XCTAssertGreaterThan([array[i] doubleValue], [array[i+1] doubleValue]);
    }
}

- (void)testScoreWithNilVariants {
    NSArray *variants = nil;
    NSDictionary *context = @{@"language": @"cowboy"};
    IMPDecisionModel *model = [[IMPDecisionModel alloc] initWithModelName:@"theme"];
    NSArray *scores = [model score:variants given:context];
    XCTAssertNotNil(scores);
    XCTAssertEqual([scores count], 0);
}

- (void)testScoreWithEmptyVariants {
    NSArray *variants = @[];
    NSDictionary *context = @{@"language": @"cowboy"};
    IMPDecisionModel *model = [[IMPDecisionModel alloc] initWithModelName:@"theme"];
    NSArray *scores = [model score:variants given:context];
    XCTAssertNotNil(scores);
    XCTAssertEqual([scores count], 0);
}

- (void)testScoreWithoutLoadingModel {
    NSMutableArray *variants = [[NSMutableArray alloc] init];
    for(int i = 0; i < 100; i++) {
        [variants addObject:@(i)];
    }
    
    NSDictionary *context = @{@"language": @"cowboy"};
    IMPDecisionModel *model = [[IMPDecisionModel alloc] initWithModelName:@"theme"];
    NSArray<NSNumber *> *scores = [model score:variants given:context];
    XCTAssertNotNil(scores);
    XCTAssertEqual([scores count], [variants count]);
    
    // assert that scores is in descending order
    NSInteger size = [variants count];
    for(int i = 0; i < size-1; ++i) {
        NSLog(@"score[%d] = %lf", i, [scores[i] doubleValue]);
        XCTAssertGreaterThan([scores[i] doubleValue], [scores[i+1] doubleValue]);
    }
}

- (void)testChooseFrom {
    NSArray *variants = @[@"Hello World", @"Howdy World", @"Hi World"];
    NSDictionary *context = @{@"language": @"cowboy"};
    for(NSURL *url in self.urlList){
        NSError *err;
        IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:&err];
        XCTAssertNotNil(decisionModel);
        XCTAssertNil(err);
        NSString *greeting = [[[decisionModel chooseFrom:variants] given:context] get];
        IMPLog("url=%@, greeting=%@", url, greeting);
        XCTAssertNotNil(greeting);
    }
}

extern NSString * const kTrackerURL;

// variants are json encodable
- (void)testChooseFromValidVariants {
    // variant must be one of type NSArray, NSDictionary, NSString, NSNumber, Boolean, or NSNull
    NSArray *variants = @[@[@"hello", @"hi"],
                          @{@"color":@"#ff0000", @"flag":@(YES), @"font":[NSNull null]},
                          @"Hi World",
                          @(3),
                          @(3.0),
                          @(YES),
                          [NSNull null]
    ];
    
    NSURL *modelUrl = [[TestUtils bundle] URLForResource:@"TestModel"
                                           withExtension:@"mlmodelc"];
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:modelUrl error:nil];
    IMPDecisionTracker *tracker = [[IMPDecisionTracker alloc] initWithTrackURL:[NSURL URLWithString:kTrackerURL]];
    [decisionModel trackWith:tracker];
    [[decisionModel chooseFrom:variants] get];
}

// variants are not json encodable
- (void)testChooseFromInvalidVariants {
    NSURL *urlVariant = [NSURL URLWithString:@"https://hello.com"];
    NSDate *dateVariant = [NSDate date];
    
    NSArray *variants = @[urlVariant, dateVariant];
    
    NSURL *modelUrl = [[TestUtils bundle] URLForResource:@"TestModel"
                                           withExtension:@"mlmodelc"];
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:modelUrl error:nil];
    IMPDecisionTracker *tracker = [[IMPDecisionTracker alloc] initWithTrackURL:[NSURL URLWithString:kTrackerURL]];
    [decisionModel trackWith:tracker];
    @try {
        [[decisionModel chooseFrom:variants] get];
    } @catch (NSException *e){
        NSLog(@"%@", e);
        return ;
    }
    XCTFail(@"We should never reach here. An exception should have been thrown.");
}

- (void)testLoadToFail {
    // url that does not exists
    NSError *err;
    NSURL *url = [NSURL URLWithString:@"http://192.168.1.101/TestModel.mlmodel3.gzs"];
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:&err];
    XCTAssertNotNil(err);
    XCTAssertNil(decisionModel);
}


- (void)testRank{
    NSMutableArray<NSNumber *> *variants = [[NSMutableArray alloc] init];
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    int size = 10;
    
    for(NSUInteger i = 0; i < size; ++i){
        variants[i] = [NSNumber numberWithInteger:i];
        scores[i] = [NSNumber numberWithDouble:i/100000.0];
    }
    
    // shuffle
    srand((unsigned int)time(0));
    for(NSUInteger i = 0; i < variants.count*10; ++i){
        NSUInteger m = rand() % variants.count;
        NSUInteger n = rand() % variants.count;
        [variants exchangeObjectAtIndex:m withObjectAtIndex:n];
        [scores exchangeObjectAtIndex:m withObjectAtIndex:n];
    }
    for(int i = 0; i < variants.count; ++i){
        NSLog(@"variant before sorting: %d", variants[i].intValue);
    }
    
    NSLog(@"\n");
    NSArray<NSNumber *> *result = [IMPDecisionModel rank:variants withScores:scores];
    
    for(NSUInteger i = 0; i+1 < variants.count; ++i){
        XCTAssert(result[i].unsignedIntValue > result[i+1].unsignedIntValue);
    }
    
    for(int i = 0; i < variants.count; ++i){
        NSLog(@"variant after sorting: %d", result[i].intValue);
    }
}

- (void)testRank_larger_variants_size {
    NSMutableArray<NSNumber *> *variants = [[NSMutableArray alloc] init];
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    int size = 10;
    
    for(NSUInteger i = 0; i < size; ++i){
        variants[i] = [NSNumber numberWithInteger:i];
        scores[i] = [NSNumber numberWithDouble:i/100000.0];
    }
    variants[size] = [NSNumber numberWithInt:size];
    
    @try {
        NSArray<NSNumber *> *result = [IMPDecisionModel rank:variants withScores:scores];
        NSLog(@"ranked size = %lu", result.count);
    } @catch (NSException *e) {
        NSLog(@"name=%@, reason=%@", e.name, e.reason);
        return ;
    }
    XCTFail(@"An exception should have been thrown, we should not have reached here.");
}

- (void)testRank_larger_scores_size {
    NSMutableArray<NSNumber *> *variants = [[NSMutableArray alloc] init];
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    int size = 10;
    
    for(NSUInteger i = 0; i < size; ++i){
        variants[i] = [NSNumber numberWithInteger:i];
        scores[i] = [NSNumber numberWithDouble:i/100000.0];
    }
    scores[size] = [NSNumber numberWithDouble:size/100000.0];
    
    @try {
        NSArray<NSNumber *> *result = [IMPDecisionModel rank:variants withScores:scores];
        NSLog(@"ranked size = %lu", result.count);
    } @catch (NSException *e) {
        NSLog(@"name=%@, reason=%@", e.name, e.reason);
        return ;
    }
    XCTFail(@"An exception should have been thrown, we should not have reached here.");
}

- (void)testTopScoringVariant{
    NSMutableArray<NSNumber *> *variants = [[NSMutableArray alloc] init];
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    int size = 10;
    
    for(NSUInteger i = 0; i < size; ++i){
        variants[i] = [NSNumber numberWithInteger:i];
        scores[i] = [NSNumber numberWithDouble:i/100000.0];
    }
    
    // shuffle
    srand((unsigned int)time(0));
    for(NSUInteger i = 0; i < variants.count; ++i){
        NSUInteger m = rand() % variants.count;
        NSUInteger n = rand() % variants.count;
        [variants exchangeObjectAtIndex:m withObjectAtIndex:n];
        [scores exchangeObjectAtIndex:m withObjectAtIndex:n];
    }
    
    NSArray<NSNumber *> *rankedResult = [IMPDecisionModel rank:variants withScores:scores];
    
    for(int i = 0; i < variants.count; ++i){
        NSLog(@"variants: %@", variants[i]);
    }
    id topScoringVariant = [IMPDecisionModel topScoringVariant:variants withScores:scores];
    NSLog(@"topScoringVariant: %@", topScoringVariant);
    XCTAssertEqual(rankedResult[0], topScoringVariant);
    
    // in case of tie, the lowest index wins
    [variants addObject:@10.1];
    [variants addObject:@10.2];
    [variants addObject:@10.3];
    
    [scores addObject:@10];
    [scores addObject:@10];
    [scores addObject:@10];
    
    topScoringVariant = [IMPDecisionModel topScoringVariant:variants withScores:scores];
    NSLog(@"topScoringVariant: %@", topScoringVariant);
    XCTAssertEqual([topScoringVariant doubleValue], 10.1);
}

// variants.count > scores.count, an exception should be thrown
- (void)testTopScoringVariant_larger_variant_size {
    NSMutableArray<NSNumber *> *variants = [[NSMutableArray alloc] init];
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    int size = 10;
    
    for(NSUInteger i = 0; i < size; ++i){
        variants[i] = [NSNumber numberWithInteger:i];
        scores[i] = [NSNumber numberWithDouble:i/100000.0];
    }
    variants[size] = [NSNumber numberWithInt:size];
    
    @try {
        [IMPDecisionModel topScoringVariant:variants withScores:scores];
    } @catch (NSException *e) {
        NSLog(@"name=%@, reason=%@", e.name, e.reason);
        return ;
    }
    XCTFail(@"An exception should have been thrown, we should not have reached here.");
}

// scores.count > variants.count, an exception should be thrown
- (void)testTopScoringVariant_larger_scores_size {
    NSMutableArray<NSNumber *> *variants = [[NSMutableArray alloc] init];
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    int size = 10;
    
    for(NSUInteger i = 0; i < size; ++i){
        variants[i] = [NSNumber numberWithInteger:i];
        scores[i] = [NSNumber numberWithDouble:i/100000.0];
    }
    scores[size] = [NSNumber numberWithDouble:size/100000.0];
    
    @try {
        [IMPDecisionModel topScoringVariant:variants withScores:scores];
    } @catch (NSException *e) {
        NSLog(@"name=%@, reason=%@", e.name, e.reason);
        return ;
    }
    XCTFail(@"An exception should have been thrown, we should not have reached here.");
}

- (void)testSetTracker {
    IMPDecisionTracker *tracker = [[IMPDecisionTracker alloc] initWithTrackURL:[NSURL URLWithString:@"tracker url"]];
    
    NSURL *url = [[TestUtils bundle] URLForResource:@"TestModel"
                                      withExtension:@"mlmodelc"];
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:url error:nil];
    XCTAssertTrue([[decisionModel trackWith:tracker] isKindOfClass:[IMPDecisionModel class]]);
    XCTAssertNotNil(decisionModel.tracker);
}

- (void)testDumpScore_11 {
    int size = 11;
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    for(int i = 0; i < size; ++i) {
        [scores addObject:@((double)arc4random() / UINT32_MAX)];
    }
    
    NSMutableArray *variants = [[NSMutableArray alloc] init];
    for(int i = 0; i < size; ++i) {
        [variants addObject:[NSString stringWithFormat:@"Hello-%d", i]];
    }
    
    for(int i = 0; i < size; ++i) {
        NSLog(@"#%d, score:%lf variant:%@", i, [scores[i] doubleValue], variants[i]);
    }
    
    [IMPUtils dumpScores:scores andVariants:variants];
    
    for(int i = 0; i < size; ++i) {
        NSLog(@"#%d, score:%lf variant:%@", i, [scores[i] doubleValue], variants[i]);
    }
}

- (void)testDumpScore_21 {
    int size = 21;
    NSMutableArray *scores = [[NSMutableArray alloc] init];
    for(int i = 0; i < size; ++i) {
        [scores addObject:@((double)arc4random() / UINT32_MAX)];
    }
    
    NSMutableArray *variants = [[NSMutableArray alloc] init];
    for(int i = 0; i < size; ++i) {
        NSDictionary *variant = @{@"greeting":@"hi", @"index":@11};
        [variants addObject:variant];
    }
    
    [IMPUtils dumpScores:scores andVariants:variants];
}

- (void)testValidateModels {
    NSURL *testsuiteURL = [[TestUtils bundle] URLForResource:@"model_test_suite.txt" withExtension:nil];
    NSString *allTestsStr = [[NSString alloc] initWithContentsOfURL:testsuiteURL encoding:NSUTF8StringEncoding error:nil];
    XCTAssertTrue(allTestsStr.length>1);
    
    if([allTestsStr hasSuffix:@"\n"]){
        allTestsStr = [allTestsStr substringToIndex:allTestsStr.length-1];
    }
    
    NSArray *allTestCases = [allTestsStr componentsSeparatedByString:@"\n"];
    XCTAssertTrue(allTestCases.count >= 1);
    
    for(NSString *testCase in allTestCases) {
        NSString *jsonFileName = [NSString stringWithFormat:@"%@.json", testCase];
        NSURL *url = [[TestUtils bundle] URLForResource:jsonFileName withExtension:nil subdirectory:testCase];
        NSData *data = [NSData dataWithContentsOfURL:url];
        XCTAssertNotNil(data);
        
        NSError *err = nil;
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        XCTAssertNil(err);
        
        XCTAssertTrue([self verifyModel:testCase withData:root]);
    }
}

- (BOOL)verifyModel:(NSString *)path withData:(NSDictionary *)root {
    NSLog(@"verifyModel: <<<<<<<< %@ >>>>>>>>", path);
    NSURL *modelURL = [[TestUtils bundle] URLForResource:@"model.mlmodel.gz" withExtension:nil subdirectory:path];
    
    NSDictionary *testCase = [root objectForKey:@"test_case"];
    XCTAssertNotNil(testCase);
    
    double noise = [[testCase objectForKey:@"noise"] doubleValue];
    NSArray *variants = [testCase objectForKey:@"variants"];
    NSArray *givens = [testCase objectForKey:@"givens"];
    NSArray *expectedOutputs = [root objectForKey:@"expected_output"];
    XCTAssertNotNil(variants);
    XCTAssertNotNil(givens);
    
    IMPDecisionModel *decisionModel = [IMPDecisionModel load:modelURL error:nil];
    decisionModel.enableTieBreaker = NO;
    decisionModel.featureEncoder.noise = noise;
    
    if([givens isEqual:[NSNull null]]) {
        NSArray *scores = [decisionModel score:variants];
        NSArray *expectedScores = [expectedOutputs[0] objectForKey:@"scores"];
        XCTAssertEqual([scores count], [expectedScores count]);
        XCTAssertTrue([scores count] > 0);
        
        for(int j = 0; j < [scores count]; ++j) {
            XCTAssertEqualWithAccuracy([expectedScores[j] doubleValue],
                                       [scores[j] doubleValue],
                                       pow(2, -18));
        }
    } else {
        for(int i = 0; i < [givens count]; ++i) {
            NSLog(@"%d/%ld", i, [givens count]);
            NSArray *scores = [decisionModel score:variants given:givens[i]];
            NSArray *expectedScores = [expectedOutputs[i] objectForKey:@"scores"];
            XCTAssertEqual([scores count], [expectedScores count]);
            XCTAssertTrue([scores count] > 0);
            
            for(int j = 0; j < [scores count]; ++j) {
//                NSLog(@"%d, %d, variant: %@\n, givens: %@", j, i, variants[j], givens[i]);
                XCTAssertEqualWithAccuracy([expectedScores[j] doubleValue],
                                           [scores[j] doubleValue],
                                           pow(2, -18));
            }
        }
    }
    return YES;
}

@end
