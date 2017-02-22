//
//  DrawingUtility.h
//  FaceDetector
//
//  Created by Mahdi Hosseini on 2/6/17.
//  Copyright © 2017 Mahdi Hosseini. All rights reserved.
//

@import Foundation;
@import UIKit;

@interface DrawingUtility : NSObject

+ (void)addCircleAtPoint:(CGPoint)point
                  toView:(UIView *)view
               withColor:(UIColor *)color
              withRadius:(NSInteger)width;

+ (void)addRectangle:(CGRect)rect
              toView:(UIView *)view
           withColor:(UIColor *)color;

+ (void)addTextLabel:(NSString *)text
              atRect:(CGRect)rect
              toView:(UIView *)view
           withColor:(UIColor *)color;

@end
