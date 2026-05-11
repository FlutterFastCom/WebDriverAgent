/** Copyright (c) 2015-present, Facebook, Inc. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
@interface FBBezierInterpolator : NSObject
+ (NSArray<NSValue *> *)pointsAlongCurveFrom:(CGPoint)start to:(CGPoint)end controlPoints:(NSArray<NSValue *> *)controlPoints steps:(NSUInteger)steps;
@end
