//
//  NSDictionary+MLFeatureProvider.h
//  ImproveUnitTests
//
//  Created by Justin Chapweske on 3/15/21.
//  Copyright © 2021 Mind Blown Apps, LLC. All rights reserved.
//

#import <CoreML/CoreML.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSDictionary (MLFeatureProvider) <MLFeatureProvider>

- (instancetype)initWithFeatureNames:(NSSet<NSString *> *)featureNames;

@end

NS_ASSUME_NONNULL_END
