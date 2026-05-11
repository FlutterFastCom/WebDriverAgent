/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBBezierInterpolator.h"
@implementation FBBezierInterpolator
+ (NSArray<NSValue *> *)pointsAlongCurveFrom:(CGPoint)start to:(CGPoint)end controlPoints:(NSArray<NSValue *> *)controlPoints steps:(NSUInteger)steps
{
  NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithObject:[NSValue valueWithCGPoint:start]]; [points addObjectsFromArray:controlPoints ?: @[]]; [points addObject:[NSValue valueWithCGPoint:end]]; NSMutableArray<NSValue *> *out = [NSMutableArray arrayWithCapacity:steps + 1];
  for (NSUInteger i = 0; i <= steps; i++) { [out addObject:[NSValue valueWithCGPoint:[self deCasteljauPointsAtT:(CGFloat)i / (CGFloat)MAX(1u, steps) controlPoints:points]]]; }
  return out;
}
+ (CGPoint)deCasteljauPointsAtT:(CGFloat)t controlPoints:(NSArray<NSValue *> *)points
{
  if (points.count <= 1) return points.count ? [points[0] CGPointValue] : CGPointZero; NSMutableArray<NSValue *> *next = [NSMutableArray arrayWithCapacity:points.count - 1]; for (NSUInteger i = 0; i + 1 < points.count; i++) { CGPoint a = [points[i] CGPointValue]; CGPoint b = [points[i + 1] CGPointValue]; [next addObject:[NSValue valueWithCGPoint:CGPointMake(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y))]]; } return [self deCasteljauPointsAtT:t controlPoints:next];
}
@end
