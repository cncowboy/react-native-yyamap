//
//  RCTAMap.m
//  RCTAMap
//
//  Created by yiyang on 16/2/26.
//  Copyright © 2016年 creditease. All rights reserved.
//

#import "RCTAMap.h"

#import "RCTEventDispatcher.h"
#import "RCTLog.h"
#import "RCTAMapAnnotation.h"
#import "RCTAMapOverlay.h"
#import "RCTUtils.h"

const CLLocationDegrees RCTAMapDefaultSpan = 0.005;
const NSTimeInterval RCTAMapRegionChangeObserveInterval = 0.1;
const CGFloat RCTAMapZoomBoundBuffer = 0.01;

@implementation RCTAMap
{
    UIView *_legalLabel;
    CLLocationManager *_locationManager;
    NSMutableArray<UIView *> *_reactSubviews;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _hasStartedRendering = NO;
        _reactSubviews = [NSMutableArray new];
        
        for (UIView *subview in self.subviews) {
            if ([NSStringFromClass(subview.class) isEqualToString:@"MKAttributionLabel"]) {
                _legalLabel = subview;
                break;
            }
        }
    }
    return self;
}

- (void)dealloc
{
    [_regionChangeObserveTimer invalidate];
}

- (void)insertReactSubview:(UIView *)subview atIndex:(NSInteger)atIndex
{
    [_reactSubviews insertObject:subview atIndex:atIndex];
}

- (void)removeReactSubviews: (UIView *)subview
{
    [_reactSubviews removeObject:subview];
}

- (NSArray<UIView *> *)reactSubviews
{
    return _reactSubviews;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    if (_legalLabel) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CGRect frame = _legalLabel.frame;
            if (_legalLabelInsets.left) {
                frame.origin.x = _legalLabelInsets.left;
            } else if (_legalLabelInsets.right) {
                frame.origin.x = self.frame.size.width - _legalLabelInsets.right - frame.size.width;
            }
            if (_legalLabelInsets.top) {
                frame.origin.y = _legalLabelInsets.top;
            } else if (_legalLabelInsets.bottom) {
                frame.origin.y = self.frame.size.height - _legalLabelInsets.bottom - frame.size.height;
            }
            _legalLabel.frame = frame;
        });
    }
}

#pragma mark - Accessors

- (void)setShowsUserLocation:(BOOL)showsUserLocation
{
    if (self.showsUserLocation != showsUserLocation) {
        if (showsUserLocation && !_locationManager) {
            _locationManager = [CLLocationManager new];
            if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
                [_locationManager requestWhenInUseAuthorization];
            }
        }
        super.showsUserLocation = showsUserLocation;
    }
}

- (void)setRegion:(MACoordinateRegion)region animated:(BOOL)animated
{
    if (!CLLocationCoordinate2DIsValid(region.center)) {
        return;
    }
    
    if (!region.span.latitudeDelta) {
        region.span.latitudeDelta = self.region.span.latitudeDelta;
    }
    if (!region.span.longitudeDelta) {
        region.span.longitudeDelta = self.region.span.longitudeDelta;
    }
    
    [super setRegion:region animated:animated];
}

- (void)setAnnotations:(NSArray<RCTAMapAnnotation *> *)annotations
{
    NSMutableArray<NSString *> *newAnnotationIDs = [NSMutableArray new];
    NSMutableArray<RCTAMapAnnotation *> *annotationsToDelete = [NSMutableArray new];
    NSMutableArray<RCTAMapAnnotation *> *annotationsToAdd = [NSMutableArray new];
    
    for (RCTAMapAnnotation *annotation in annotations) {
        if (![annotation isKindOfClass:[RCTAMapAnnotation class]]) {
            continue;
        }
        
        [newAnnotationIDs addObject:annotation.identifier];
        
        if (![_annotationIDs containsObject:annotation.identifier]) {
            [annotationsToAdd addObject:annotation];
        }
    }
    for (RCTAMapAnnotation *annotation in self.annotations) {
        if (![annotations isKindOfClass:[RCTAMapAnnotation class]]) {
            continue;
        }
        
        if (![newAnnotationIDs containsObject:annotation.identifier]) {
            [annotationsToDelete addObject:annotation];
        }
    }
    
    if (annotationsToDelete.count > 0) {
        [self removeAnnotations:(NSArray<id<MAAnnotation>> *)annotationsToDelete];
    }
    
    if (annotationsToAdd.count > 0) {
        [self addAnnotations:(NSArray<id<MAAnnotation>> *)annotationsToAdd];
    }
    
    self.annotationIDs = newAnnotationIDs;
}

- (void)setOverlays:(NSArray<RCTAMapOverlay *> *)overlays
{
    NSMutableArray<NSString *> *newOverlayIDs = [NSMutableArray new];
    NSMutableArray<RCTAMapOverlay *> *overlaysToDelete = [NSMutableArray new];
    NSMutableArray<RCTAMapOverlay *> *overlaysToAdd = [NSMutableArray new];
    
    for (RCTAMapOverlay *overlay in overlays) {
        if (![overlay isKindOfClass:[RCTAMapOverlay class]]) {
            continue;
        }
        
        [newOverlayIDs addObject:overlay.identifier];
        
        if (![_overlayIDs containsObject:overlay.identifier]) {
            [overlaysToAdd addObject:overlay];
        }
    }
    
    for (RCTAMapOverlay *overlay in self.overlays) {
        if (![overlay isKindOfClass:[RCTAMapOverlay class]]) {
            continue;
        }
        
        if (![newOverlayIDs containsObject:overlay.identifier]) {
            [overlaysToDelete addObject:overlay];
        }
    }
    
    if (overlaysToDelete.count > 0) {
        [self removeOverlays:(NSArray<id<MAOverlay>> *)overlaysToDelete];
    }
    if (overlaysToAdd.count > 0) {
        [self addOverlays:(NSArray<id<MAOverlay>> *)overlaysToAdd];
    }
    
    self.overlayIDs = newOverlayIDs;
}

- (BOOL)showsCompass {
    if ([MAMapView instancesRespondToSelector:@selector(showsCompass)]) {
        return super.showsCompass;
    }
    return NO;
}

- (void)setShowsCompass:(BOOL)showsCompass {
    if ([MAMapView instancesRespondToSelector:@selector(setShowsCompass:)]) {
        super.showsCompass = showsCompass;
    }
}

- (void)zoomToSpan:(NSArray<RCTAMapAnnotation *> *)annotations andOverlays:(NSArray<RCTAMapOverlay *> *)overlays
{
    CLLocationDegrees minLat = 0.0;
    CLLocationDegrees maxLat = 0.0;
    CLLocationDegrees minLon = 0.0;
    CLLocationDegrees maxLon = 0.0;
    BOOL hasInitialized = NO;
    NSInteger index = 0;
    if (annotations != nil) {
        for (RCTAMapAnnotation *annotation in annotations) {
            if (index == 0 && hasInitialized == NO) {
                minLat = maxLat = annotation.coordinate.latitude;
                minLon = maxLon = annotation.coordinate.longitude;
                hasInitialized = YES;
            } else {
                minLat = MIN(minLat, annotation.coordinate.latitude);
                minLon = MIN(minLon, annotation.coordinate.longitude);
                maxLat = MAX(maxLat, annotation.coordinate.latitude);
                maxLon = MAX(maxLon, annotation.coordinate.longitude);
            }
            index ++;
        }
    }
    index = 0;
    if (overlays != nil) {
        for (RCTAMapOverlay *overlay in overlays) {
            for (NSInteger i = 0; i < overlay.pointCount; i++) {
                MAMapPoint pt = overlay.points[i];
                CLLocationCoordinate2D coordinate = MACoordinateForMapPoint(pt);
                if (index == 0 && i == 0 && hasInitialized == NO) {
                    minLat = maxLat = coordinate.latitude;
                    minLon = maxLon = coordinate.longitude;
                    hasInitialized = YES;
                } else {
                    minLat = MIN(minLat, coordinate.latitude);
                    minLon = MIN(minLon, coordinate.longitude);
                    maxLat = MAX(maxLat, coordinate.latitude);
                    maxLon = MAX(maxLon, coordinate.longitude);
                }
            }
            index ++;
        }
    }
    
    if (hasInitialized) {
        CLLocationCoordinate2D center;
        center.latitude = (maxLat + minLat) * .5f;
        center.longitude = (minLon + maxLon) * .5f;
        MACoordinateSpan span = MACoordinateSpanMake(maxLat - minLat + 0.02, maxLon - minLon + 0.02);
        
        MACoordinateRegion region = MACoordinateRegionMake(center, span);
        
        [self setRegion:region animated:YES];
    }
}

- (void)zoomToSpan
{
    [self zoomToSpan:self.annotations andOverlays:self.overlays];
}

- (void)zoomToSpan:(NSArray<CLLocation *> *)locations
{
    if (locations == nil || locations.count == 0) {
        [self zoomToSpan];
    } else if (locations.count == 1) {
        CLLocation *onlyLocation = locations.firstObject;
        [self zoomToCenter:onlyLocation.coordinate];
    } else {
        CLLocationDegrees minLat = 0.0;
        CLLocationDegrees maxLat = 0.0;
        CLLocationDegrees minLon = 0.0;
        CLLocationDegrees maxLon = 0.0;
        NSInteger index = 0;
        for (CLLocation *location in locations) {
            if (index == 0) {
                minLat = maxLat = location.coordinate.latitude;
                minLon = maxLon = location.coordinate.longitude;
            } else {
                minLat = MIN(minLat, location.coordinate.latitude);
                minLon = MIN(minLon, location.coordinate.longitude);
                maxLat = MAX(maxLat, location.coordinate.latitude);
                maxLon = MAX(maxLon, location.coordinate.longitude);
            }
            index ++;
        }
        
        CLLocationCoordinate2D center;
        center.latitude = (maxLat + minLat) * .5f;
        center.longitude = (minLon + maxLon) * .5f;
        MACoordinateSpan span = MACoordinateSpanMake(maxLat - minLat + 0.02, maxLon - minLon + 0.02);
        
        MACoordinateRegion region = MACoordinateRegionMake(center, span);
        
        [self setRegion:region animated:YES];
        
    }
}

- (BOOL)isValidLon:(float)lon lat:(float)lat {//判断经纬度是否合法
    if (ABS(lon)>180 || ABS(lat)>90) {
        return NO;
    }
    return YES;
}

- (void)zoomToCenter:(CLLocationCoordinate2D)coordinate
{
    float longitude = coordinate.longitude;
    float latitude = coordinate.latitude;
    if (![self isValidLon:longitude lat:latitude]) {
        return;
    }
    BOOL animation = TRUE;
    [super setCenterCoordinate:coordinate animated:animation];
    [super setZoomLevel:19 animated:animation];
}

@end
