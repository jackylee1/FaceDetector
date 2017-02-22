//
//  DrawingUtility.m
//  FaceDetector
//
//  Created by Mahdi Hosseini on 2/6/17.
//  Copyright © 2017 Mahdi Hosseini. All rights reserved.
//

#import "DrawingUtility.h"

@implementation DrawingUtility

+ (void)addCircleAtPoint:(CGPoint)point
                  toView:(UIView *)view
               withColor:(UIColor *)color
              withRadius:(NSInteger)width {
    CGRect circleRect = CGRectMake(point.x - width / 2, point.y - width / 2, width, width);
    UIView *circleView = [[UIView alloc] initWithFrame:circleRect];
    circleView.layer.cornerRadius = width / 2;
    circleView.alpha = 0.7;
    circleView.backgroundColor = color;
    [view addSubview:circleView];
}

+ (void)addRectangle:(CGRect)rect
              toView:(UIView *)view
           withColor:(UIColor *)color {
    UIView *newView = [[UIView alloc] initWithFrame:rect];
    newView.layer.cornerRadius = 10;
    newView.alpha = 0.3;
    newView.backgroundColor = color;
    [view addSubview:newView];
}

+ (void)addTextLabel:(NSString *)text
              atRect:(CGRect)rect
              toView:(UIView *)view
           withColor:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:rect];
    [label setTextColor:color];
    label.text = text;
    [view addSubview:label];
}

@end
