//
//  CameraViewController.m
//  FaceDetector
//
//  Created by Mahdi Hosseini on 2/6/17.
//  Copyright © 2017 Mahdi Hosseini. All rights reserved.
//

@import AWSS3;
@import AVFoundation;
@import GoogleMobileVision;

#import "CameraViewController.h"
#import "LocationManager.h"
#import "DrawingUtility.h"
#import "Constants.h"

LocationManager *locationManagerSharedInstance;
NSString *const PhoneNumber = @"+11234567890 ";

@interface CameraViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate>

// UI elements.
@property(nonatomic, weak) IBOutlet UIView *placeHolder;
@property(nonatomic, weak) IBOutlet UIView *overlayView;
@property(nonatomic, weak) IBOutlet UISwitch *cameraSwitch;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;

// Video objects.
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property(nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property(nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property(nonatomic, strong) AVCapturePhotoSettings *photoSettings;

@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, assign) UIDeviceOrientation lastKnownDeviceOrientation;

@property(nonatomic, strong) UIImage* faceImage;

@property (nonatomic, strong) NSMutableArray *collection;

// Location Manager
@property (strong, nonatomic) CLLocationManager* locationManager;
@property (strong, nonatomic) CLLocation* currentLocation;
@property (strong, nonatomic) CLPlacemark* currentLocationPlacemark;
@property (strong, nonatomic) NSNumber *faceDetected;



// Detector.
@property(nonatomic, strong) GMVDetector *faceDetector;

@end

@implementation CameraViewController

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue",
                                                          DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.faceDetected = [[NSNumber alloc]init];
    
    
    // Location Manager
    
    locationManagerSharedInstance = [LocationManager sharedInstance];
    
    [[LocationManager sharedInstance] addObserver:self forKeyPath:@"currentLocation" options:NSKeyValueObservingOptionNew context:nil];
    [[LocationManager sharedInstance] addObserver:self forKeyPath:@"currentLocationPlacemark" options:NSKeyValueObservingOptionNew context:nil];
    
    
    self.collection = [NSMutableArray new];

    
    NSError *error = nil;
    
    NSString *basePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[basePath stringByAppendingPathComponent:@"upload"]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        NSLog(@"Creating 'upload' directory failed: [%@]", error);
    }
    
    
    // Set up default camera settings.
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetMedium;
    self.cameraSwitch.on = YES;
    [self updateCameraSelection];
    
    // Set up photo capture settings
    self.photoOutput = [[AVCapturePhotoOutput alloc] init];
    self.photoSettings = [AVCapturePhotoSettings photoSettings];
    
    //AVCaptureConnection *photoOutputConnection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
    
    if ( [self.session canAddOutput:self.photoOutput] ) {
        [self.session addOutput:self.photoOutput];
        
        self.photoOutput.highResolutionCaptureEnabled = YES;
        self.photoOutput.livePhotoCaptureEnabled = NO;
    }
    
    // Setup video processing pipeline.
    [self setupVideoProcessing];
    
    // Setup camera preview.
    [self setupCameraPreview];
    
    // Initialize the face detector.
    NSDictionary *options = @{
                              GMVDetectorFaceMinSize : @(0.3),
                              GMVDetectorFaceTrackingEnabled : @(YES),
                              GMVDetectorFaceLandmarkType : @(GMVDetectorFaceLandmarkAll)
                              };
    self.faceDetector = [GMVDetector detectorOfType:GMVDetectorTypeFace options:options];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    self.previewLayer.frame = self.view.layer.bounds;
    self.previewLayer.position = CGPointMake(CGRectGetMidX(self.previewLayer.frame),
                                             CGRectGetMidY(self.previewLayer.frame));
}

- (void)viewDidUnload {
    [self cleanupCaptureSession];
    [super viewDidUnload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.session startRunning];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.session stopRunning];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                         duration:(NSTimeInterval)duration {
    // Camera rotation needs to be manually set when rotation changes.
    if (self.previewLayer) {
        if (toInterfaceOrientation == UIInterfaceOrientationPortrait) {
            self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
        } else if (toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
            self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
        } else if (toInterfaceOrientation == UIInterfaceOrientationLandscapeLeft) {
            self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
        } else if (toInterfaceOrientation == UIInterfaceOrientationLandscapeRight) {
            self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
        }
    }
}

#pragma mark - AVCaptureVideoPreviewLayer Helper method

- (CGRect)scaledRect:(CGRect)rect
              xScale:(CGFloat)xscale
              yScale:(CGFloat)yscale
              offset:(CGPoint)offset {
    CGRect resultRect = CGRectMake(rect.origin.x * xscale,
                                   rect.origin.y * yscale,
                                   rect.size.width * xscale,
                                   rect.size.height * yscale);
    resultRect = CGRectOffset(resultRect, offset.x, offset.y);
    return resultRect;
}

- (CGPoint)scaledPoint:(CGPoint)point
                xScale:(CGFloat)xscale
                yScale:(CGFloat)yscale
                offset:(CGPoint)offset {
    CGPoint resultPoint = CGPointMake(point.x * xscale + offset.x, point.y * yscale + offset.y);
    return resultPoint;
}

- (void)setLastKnownDeviceOrientation:(UIDeviceOrientation)orientation {
    if (orientation != UIDeviceOrientationUnknown &&
        orientation != UIDeviceOrientationFaceUp &&
        orientation != UIDeviceOrientationFaceDown) {
        _lastKnownDeviceOrientation = orientation;
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)capturePhoto {
    AVCapturePhotoSettings* uniqueSettings = [AVCapturePhotoSettings photoSettingsFromPhotoSettings:self.photoSettings];
    [self.photoOutput capturePhotoWithSettings:uniqueSettings delegate:self];
    NSLog(@"Captured photo");
}


- (void)uploadWrapper {
    NSString *basePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingString:@".png"];
    NSString *filePath = [[basePath stringByAppendingPathComponent:@"upload"] stringByAppendingPathComponent:fileName];
    NSData *imageData = UIImagePNGRepresentation(self.faceImage);
    
    [imageData writeToFile:filePath atomically:YES];
    
    AWSS3TransferManagerUploadRequest *uploadRequest = [AWSS3TransferManagerUploadRequest new];
    uploadRequest.body = [NSURL fileURLWithPath:filePath];
    uploadRequest.key = fileName;
    uploadRequest.bucket = S3BucketName;
    
    [self.collection insertObject:uploadRequest atIndex:0];
    
    [self upload:uploadRequest];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    UIImage *image = [GMVUtility sampleBufferTo32RGBA:sampleBuffer];
    AVCaptureDevicePosition devicePosition = self.cameraSwitch.isOn ? AVCaptureDevicePositionFront :
    AVCaptureDevicePositionBack;
    
    // Establish the image orientation.
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    GMVImageOrientation orientation = [GMVUtility
                                       imageOrientationFromOrientation:deviceOrientation
                                       withCaptureDevicePosition:devicePosition
                                       defaultDeviceOrientation:self.lastKnownDeviceOrientation];
    NSDictionary *options = @{
                              GMVDetectorImageOrientation : @(orientation)
                              };
    // Detect features using GMVDetector.
    NSArray<GMVFaceFeature *> *faces = [self.faceDetector featuresInImage:image options:options];
    
    if ([faces count] > 0)
    {
        NSLog(@"Detected %lu face(s).", (unsigned long)[faces count]);
        
        
        if (!self.faceImage)
        {
            [self capturePhoto];
            [locationManagerSharedInstance startUpdatingLocation];
        }
    }
    
    // The video frames captured by the camera are a different size than the video preview.
    // Calculates the scale factors and offset to properly display the features.
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false);
    CGSize parentFrameSize = self.previewLayer.frame.size;
    
    // Assume AVLayerVideoGravityResizeAspect
    CGFloat cameraRatio = clap.size.height / clap.size.width;
    CGFloat viewRatio = parentFrameSize.width / parentFrameSize.height;
    CGFloat xScale = 1;
    CGFloat yScale = 1;
    CGRect videoBox = CGRectZero;
    if (viewRatio > cameraRatio) {
        videoBox.size.width = parentFrameSize.height * clap.size.width / clap.size.height;
        videoBox.size.height = parentFrameSize.height;
        videoBox.origin.x = (parentFrameSize.width - videoBox.size.width) / 2;
        videoBox.origin.y = (videoBox.size.height - parentFrameSize.height) / 2;
        
        xScale = videoBox.size.width / clap.size.width;
        yScale = videoBox.size.height / clap.size.height;
    } else {
        videoBox.size.width = parentFrameSize.width;
        videoBox.size.height = clap.size.width * (parentFrameSize.width / clap.size.height);
        videoBox.origin.x = (videoBox.size.width - parentFrameSize.width) / 2;
        videoBox.origin.y = (parentFrameSize.height - videoBox.size.height) / 2;
        
        xScale = videoBox.size.width / clap.size.height;
        yScale = videoBox.size.height / clap.size.width;
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        // Remove previously added feature views.
        for (UIView *featureView in self.overlayView.subviews) {
            [featureView removeFromSuperview];
        }
        
        // Display detected features in overlay.
        for (GMVFaceFeature *face in faces) {
            CGRect faceRect = [self scaledRect:face.bounds
                                        xScale:xScale
                                        yScale:yScale
                                        offset:videoBox.origin];
            [DrawingUtility addRectangle:faceRect
                                  toView:self.overlayView
                               withColor:[UIColor redColor]];
            
            // Mouth
            if (face.hasBottomMouthPosition) {
                CGPoint point = [self scaledPoint:face.bottomMouthPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor greenColor]
                                      withRadius:5];
            }
            if (face.hasMouthPosition) {
                CGPoint point = [self scaledPoint:face.mouthPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor greenColor]
                                      withRadius:10];
            }
            if (face.hasRightMouthPosition) {
                CGPoint point = [self scaledPoint:face.rightMouthPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor greenColor]
                                      withRadius:5];
            }
            if (face.hasLeftMouthPosition) {
                CGPoint point = [self scaledPoint:face.leftMouthPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor greenColor]
                                      withRadius:5];
            }
            
            // Nose
            if (face.hasNoseBasePosition) {
                CGPoint point = [self scaledPoint:face.noseBasePosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor darkGrayColor]
                                      withRadius:10];
            }
            
            // Eyes
            if (face.hasLeftEyePosition) {
                CGPoint point = [self scaledPoint:face.leftEyePosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor blueColor]
                                      withRadius:10];
            }
            if (face.hasRightEyePosition) {
                CGPoint point = [self scaledPoint:face.rightEyePosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor blueColor]
                                      withRadius:10];
            }
            
            // Ears
            if (face.hasLeftEarPosition) {
                CGPoint point = [self scaledPoint:face.leftEarPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor purpleColor]
                                      withRadius:10];
            }
            if (face.hasRightEarPosition) {
                CGPoint point = [self scaledPoint:face.rightEarPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor purpleColor]
                                      withRadius:10];
            }
            
            // Cheeks
            if (face.hasLeftCheekPosition) {
                CGPoint point = [self scaledPoint:face.leftCheekPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor magentaColor]
                                      withRadius:10];
            }
            if (face.hasRightCheekPosition) {
                CGPoint point = [self scaledPoint:face.rightCheekPosition
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                [DrawingUtility addCircleAtPoint:point
                                          toView:self.overlayView
                                       withColor:[UIColor magentaColor]
                                      withRadius:10];
            }
            
            // Tracking Id.
            if (face.hasTrackingID) {
                CGPoint point = [self scaledPoint:face.bounds.origin
                                           xScale:xScale
                                           yScale:yScale
                                           offset:videoBox.origin];
                UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(point.x, point.y, 100, 20)];
                label.text = [NSString stringWithFormat:@"id: %lu", (unsigned long)face.trackingID];
                [self.overlayView addSubview:label];
            }
        }
    });
}

#pragma mark - Camera setup

- (void)cleanupVideoProcessing {
    if (self.videoDataOutput) {
        [self.session removeOutput:self.videoDataOutput];
    }
    self.videoDataOutput = nil;
}

- (void)cleanupCaptureSession {
    [self.session stopRunning];
    [self cleanupVideoProcessing];
    self.session = nil;
    [self.previewLayer removeFromSuperlayer];
}

- (void)setupVideoProcessing {
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSDictionary *rgbOutputSettings = @{
                                        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
                                        };
    [self.videoDataOutput setVideoSettings:rgbOutputSettings];
    
    if (![self.session canAddOutput:self.videoDataOutput]) {
        [self cleanupVideoProcessing];
        NSLog(@"Failed to setup video output");
        return;
    }
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    [self.session addOutput:self.videoDataOutput];
}

- (void)setupCameraPreview {
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.previewLayer setBackgroundColor:[[UIColor whiteColor] CGColor]];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    CALayer *rootLayer = [self.placeHolder layer];
    [rootLayer setMasksToBounds:YES];
    [self.previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:self.previewLayer];
}

- (void)updateCameraSelection {
    [self.session beginConfiguration];
    
    // Remove old inputs
    NSArray *oldInputs = [self.session inputs];
    for (AVCaptureInput *oldInput in oldInputs) {
        [self.session removeInput:oldInput];
    }
    
    AVCaptureDevicePosition desiredPosition = self.cameraSwitch.isOn ?
    AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    AVCaptureDeviceInput *input = [self cameraForPosition:desiredPosition];
    if (!input) {
        // Failed, restore old inputs
        for (AVCaptureInput *oldInput in oldInputs) {
            [self.session addInput:oldInput];
        }
    } else {
        // Succeeded, set input and update connection states
        [self.session addInput:input];
    }
    
    [self.session commitConfiguration];
}

- (AVCaptureDeviceInput *)cameraForPosition:(AVCaptureDevicePosition)desiredPosition {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([device position] == desiredPosition) {
            NSError *error = nil;
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                                error:&error];
            
            if ([self.session canAddInput:input]) {
                
                
                return input;
            }
        }
    }
    return nil;
}

#pragma mark - AVCapturePhotoCaptureDelegate
-(void)captureOutput:(AVCapturePhotoOutput *)captureOutput didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings error:(NSError *)error
{
    if (error) {
        NSLog(@"error : %@", error.localizedDescription);
    }
    
    if (photoSampleBuffer) {
        NSData *data = [AVCapturePhotoOutput JPEGPhotoDataRepresentationForJPEGSampleBuffer:photoSampleBuffer previewPhotoSampleBuffer:previewPhotoSampleBuffer];
        self.faceImage = [UIImage imageWithData:data];
        
        [self uploadWrapper];
        
        NSLog(@"%@",[self.faceImage description]);
    }
}

- (IBAction)cameraDeviceChanged:(id)sender {
    [self updateCameraSelection];
}


#pragma mark - Amazon S3

- (void)upload:(AWSS3TransferManagerUploadRequest *)uploadRequest {
    AWSS3TransferManager *transferManager = [AWSS3TransferManager defaultS3TransferManager];
    
    __weak CameraViewController *weakSelf = self;
    
    NSLog(@"Upload request:/n%@",uploadRequest);
    
    [[transferManager upload:uploadRequest] continueWithBlock:^id(AWSTask *task) {
        if (task.error) {
            if ([task.error.domain isEqualToString:AWSS3TransferManagerErrorDomain]) {
                switch (task.error.code) {
                    case AWSS3TransferManagerErrorCancelled:
                    case AWSS3TransferManagerErrorPaused:
                    default:
                        NSLog(@"Upload failed: [%@]", task.error);
                        break;
                }
            } else {
                NSLog(@"Upload failed: [%@]", task.error);
            }
        }
        
        if (task.result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CameraViewController *strongSelf = weakSelf;
                NSUInteger index = [strongSelf.collection indexOfObject:uploadRequest];
                [strongSelf.collection replaceObjectAtIndex:index withObject:uploadRequest.body];
            });
        }
        
        return nil;
    }];
}

- (void)cancelAllUploads:(id)sender {
    [self.collection enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[AWSS3TransferManagerUploadRequest class]]) {
            AWSS3TransferManagerUploadRequest *uploadRequest = obj;
            [[uploadRequest cancel] continueWithBlock:^id(AWSTask *task) {
                if (task.error) {
                    NSLog(@"The cancel request failed: [%@]", task.error);
                }
                return nil;
            }];
        }
    }];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"currentLocation"])
    {
        [locationManagerSharedInstance stopUpdatingLocation];
        
        self.currentLocation = locationManagerSharedInstance.currentLocation;
    }
    
    if ([keyPath isEqualToString:@"currentLocationPlacemark"])
    {
        
        BOOL faceDetected = [self.faceDetected intValue] ? 1 : 0;
        
        if (self.faceImage)
        {
            if (!faceDetected) {
                self.currentLocationPlacemark = locationManagerSharedInstance.currentLocationPlacemark;
                
                [self sendSMS];
            }
        }
    }
}

#pragma mark - Twilio SMS

- (void)sendSMS {
    
    self.faceDetected = [NSNumber numberWithInt:1];
    
    NSString* currentLocationName = [NSString stringWithFormat:@"Intruder detected in: %@, %@", [self.currentLocationPlacemark locality], [self.currentLocationPlacemark administrativeArea]];
    
    self.statusLabel.text = currentLocationName;
    
    NSString* locationCoordinates = [NSString stringWithFormat:@"Coordinates: +%f, %f", self.currentLocation.coordinate.latitude, self.currentLocation.coordinate.longitude];
    
    NSDateFormatter *DateFormatter=[[NSDateFormatter alloc] init];
    
    [DateFormatter setDateFormat:@"yyyy-MM-dd hh:mm:ss"];
    
    NSString *currentTime = [DateFormatter stringFromDate:[NSDate date]];
    
    NSString *detectionTime = [NSString stringWithFormat:@"Detection time: %@", currentTime];
    
    NSString *smsBody = [NSString stringWithFormat:@"%@. %@. %@.", currentLocationName, locationCoordinates, detectionTime];
    
    // Create a new NSURLSession
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    
    NSURL *url = [NSURL URLWithString:@"https://voice-server-3435.herokuapp.com/sms"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    
    NSString *phoneNumber = PhoneNumber;
    NSString *query = [NSString stringWithFormat:@"To=%@&Body=%@",phoneNumber,smsBody];
    NSString *bodyData = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    request.HTTPMethod = @"POST";
    request.HTTPBody = [bodyData dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest: request
                                            completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error)
                                  {
                                      NSLog(@"resp: %@, err: %@", response, error);
                                  }];
    [task resume];
    
    
    NSLog(@"%@", smsBody);
}




@end
