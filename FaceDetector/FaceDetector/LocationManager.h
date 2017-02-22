//
//  LocationManager.h
//  FaceDetector
//
//  Created by Mahdi Hosseini on 2/7/17.
//  Copyright © 2017 Mahdi Hosseini. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface LocationManager : NSObject <CLLocationManagerDelegate>

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *currentLocation;
@property (nonatomic, strong) CLPlacemark *currentLocationPlacemark;

+ (LocationManager*) sharedInstance;

- (void)startUpdatingLocation;
- (void)stopUpdatingLocation;

@end
