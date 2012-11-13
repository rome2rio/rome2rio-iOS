//
//  R2RMapHelper.m
//  Rome2Rio
//
//  Created by Ash Verdoorn on 17/10/12.
//  Copyright (c) 2012 Rome2Rio. All rights reserved.
//

#import "R2RMapHelper.h"
#import "R2RSegmentHelper.h"
#import "R2RFlightSegment.h"
#import "R2RFlightItinerary.h"
#import "R2RFlightLeg.h"
#import "R2RFlightHop.h"
#import "R2RTransitSegment.h"
#import "R2RWalkDriveSegment.h"

#import "R2RConstants.h"
#import "R2RPath.h"
#import "R2RPathEncoder.h"


@interface R2RMapHelper()

@property (strong, nonatomic) R2RSearchStore *dataStore;

@end

@implementation R2RMapHelper

-(id)initWithData:(R2RSearchStore *)dataStore
{
    self = [super init];
    if (self)
    {
        self.dataStore = dataStore;
    }
    return self;
}

-(MKMapRect)getSegmentBounds:(id)segment
{
    MKMapRect rect = MKMapRectNull;
    
    R2RSegmentHelper *segmentHelper = [[R2RSegmentHelper alloc] initWithData:self.dataStore];
    
    MKMapPoint sPoint = MKMapPointFromPosition([segmentHelper getSegmentSPos:segment]);
    rect = MKMapRectGrow(rect, sPoint);
    
    MKMapPoint tPoint = MKMapPointFromPosition([segmentHelper getSegmentTPos:segment]);
    rect = MKMapRectGrow(rect, tPoint);
    
    NSString *pathString = [segmentHelper getSegmentPath:segment];
    if (pathString.length > 0)
    {
        R2RPath *path = [R2RPathEncoder decode:pathString];
        
        for (R2RPosition *pos in path.positions)
        {
            MKMapPoint point = MKMapPointFromPosition(pos);
            rect = MKMapRectGrow(rect, point);
        }
    }
    
    return rect;
}

static MKMapPoint MKMapPointFromPosition(R2RPosition *pos)
{
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(pos.lat, pos.lng);
    MKMapPoint mapPoint = MKMapPointForCoordinate(coord);
    
    return mapPoint;
}

static MKMapRect MKMapRectGrow(MKMapRect rect, MKMapPoint point)
{
    MKMapRect pointRect = MKMapRectMake(point.x, point.y, 0, 0);
    
    rect = MKMapRectUnion(rect, pointRect);
    
    return rect;
}

//return an array containing a polyline for each hop
-(NSArray *) getPolylines:(id) segment;
{
    R2RSegmentHelper *segmentHandler = [[R2RSegmentHelper alloc] init];
    NSString *kind = [segmentHandler getSegmentKind:segment];
    if ([kind isEqualToString:@"flight"])
    {
        return  [self getFlightPolylines:segment];
    }
    else if ([kind isEqualToString:@"train"])
    {
        return [self getTrainPolylines:segment];
    }
    else if ([kind isEqualToString:@"bus"])
    {
        return [self getBusPolylines:segment];
    }
    else if ([kind isEqualToString:@"ferry"])
    {
        return [self getFerryPolylines:segment];
    }
    else if ([kind isEqualToString:@"car"] || [kind isEqualToString:@"walk"])
    {
        return [self getWalkDrivePolylines:segment];
    }
    else
    {
        return nil;
    }
}

-(NSArray *) getFlightPolylines: (R2RFlightSegment *) segment
{
    R2RFlightItinerary *itinerary = [segment.itineraries objectAtIndex:0];
    R2RFlightLeg *leg = [itinerary.legs objectAtIndex:0];
    
    //TODO add geodesic Interpolation to flight path
    // for now there is just straight lines between stops
    
    NSMutableArray *array = [[NSMutableArray alloc] init];
    
    for (R2RFlightHop *hop in leg.hops)
    {
        R2RAirport *sAirport = [self.dataStore getAirport:hop.sCode];
        CLLocationCoordinate2D sPos = CLLocationCoordinate2DMake(sAirport.pos.lat, sAirport.pos.lng);
        
        R2RAirport *tAirport = [self.dataStore getAirport:hop.tCode];
        CLLocationCoordinate2D tPos = CLLocationCoordinate2DMake(tAirport.pos.lat, tAirport.pos.lng);
        
        if ((tPos.longitude - sPos.longitude) > 180 || (tPos.longitude - sPos.longitude) < -180)
        {
            MKMapPoint points[2];
            CLLocationCoordinate2D mPos;
            
            // add polyline for source to edge of map
            mPos.latitude = (tPos.latitude + sPos.latitude)/2;
            mPos.longitude = (sPos.longitude < 0) ? -180.0f : 180.0f;
            
            points[0] = MKMapPointForCoordinate(sPos);
            points[1] = MKMapPointForCoordinate(mPos);
            
            R2RFlightPolyline *polyline = (R2RFlightPolyline *)[R2RFlightPolyline polylineWithPoints:points count:2];
            [array addObject:polyline];
            
            // add polyline for edge of map to target
            mPos.longitude = -mPos.longitude;
            
            points[0] = MKMapPointForCoordinate(mPos);
            points[1] = MKMapPointForCoordinate(tPos);
            
            polyline = (R2RFlightPolyline *)[R2RFlightPolyline polylineWithPoints:points count:2];
            [array addObject:polyline];
        }
        else
        {
            MKMapPoint points[2];
            points[0] = MKMapPointForCoordinate(sPos);
            points[1] = MKMapPointForCoordinate(tPos);
            
            R2RFlightPolyline *polyline = (R2RFlightPolyline *)[R2RFlightPolyline polylineWithPoints:points count:2];
            [array addObject:polyline];
        }
    }
    
    return array;
}

-(NSArray *) getTrainPolylines: (R2RTransitSegment *) segment
{
    R2RPath *path = [R2RPathEncoder decode:segment.path];
    
    MKMapPoint points[[path.positions count]];
    NSUInteger count = 0;
    
    for (R2RPosition *pos in path.positions)
    {
        points[count++] = MKMapPointFromPosition(pos);
    }
    
    R2RTrainPolyline *polyline = (R2RTrainPolyline *)[R2RTrainPolyline polylineWithPoints:points count:count];
    NSArray *array = [[NSArray alloc] initWithObjects:polyline, nil];
    
    return array;
}

-(NSArray *) getBusPolylines: (R2RTransitSegment *) segment
{
    R2RPath *path = [R2RPathEncoder decode:segment.path];
    
    MKMapPoint points[[path.positions count]];
    NSUInteger count = 0;
    
    for (R2RPosition *pos in path.positions)
    {
        points[count++] = MKMapPointFromPosition(pos);
    }
    
    R2RBusPolyline *polyline = (R2RBusPolyline *)[R2RBusPolyline polylineWithPoints:points count:count];
    NSArray *array = [[NSArray alloc] initWithObjects:polyline, nil];
    
    return array;
}

-(NSArray *) getFerryPolylines: (R2RTransitSegment *) segment
{
    R2RPath *path = [R2RPathEncoder decode:segment.path];
    
    MKMapPoint points[[path.positions count]];
    NSUInteger count = 0;
    
    for (R2RPosition *pos in path.positions)
    {
        points[count++] = MKMapPointFromPosition(pos);
    }
    
    R2RFerryPolyline *polyline = (R2RFerryPolyline *)[R2RFerryPolyline polylineWithPoints:points count:count];
    NSArray *array = [[NSArray alloc] initWithObjects:polyline, nil];
    
    return array;
}

-(NSArray *) getWalkDrivePolylines: (R2RWalkDriveSegment *) segment
{
    R2RPath *path = [R2RPathEncoder decode:segment.path];
    
    MKMapPoint points[[path.positions count]];
    NSUInteger count = 0;
    
    for (R2RPosition *pos in path.positions)
    {
        points[count++] = MKMapPointFromPosition(pos);
    }
    
    R2RWalkDrivePolyline *polyline = (R2RWalkDrivePolyline *)[R2RWalkDrivePolyline polylineWithPoints:points count:count];
    NSArray *array = [[NSArray alloc] initWithObjects:polyline, nil];
    
    return array;
}

-(id)getPolylineView:(id)polyline
{
    if ([polyline isKindOfClass:[R2RFlightPolyline class]])
    {
        return [[R2RFlightPolylineView alloc] initWithPolyline:polyline];
    }
    else if ([polyline isKindOfClass:[R2RBusPolyline class]])
    {
        return [[R2RBusPolylineView alloc] initWithPolyline:polyline];
    }
    else if ([polyline isKindOfClass:[R2RTrainPolyline class]])
    {
        return [[R2RTrainPolylineView alloc] initWithPolyline:polyline];
    }
    else if ([polyline isKindOfClass:[R2RFerryPolyline class]])
    {
        return [[R2RFerryPolylineView alloc] initWithPolyline:polyline];
    }
    else if ([polyline isKindOfClass:[R2RWalkDrivePolyline class]])
    {
        return [[R2RWalkDrivePolylineView alloc] initWithPolyline:polyline];
    }
    else
    {
        return [[MKPolylineView alloc] initWithPolyline:polyline];
    }
}

-(id)getAnnotationView:(MKMapView *)mapView :(id<MKAnnotation>)annotation
{
    static NSString *identifier = @"R2RhopAnnotation";
    if ([annotation isKindOfClass:[R2RHopAnnotation class]])
    {
        MKAnnotationView *annotationView = (MKAnnotationView *) [mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (annotationView == nil)
        {
            annotationView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            annotationView.enabled = YES;
            annotationView.canShowCallout = YES;
            CGPoint iconOffset = CGPointMake(267, 46);
            CGSize iconSize = CGSizeMake (12, 12);
            
            R2RSprite *sprite = [[R2RSprite alloc] initWithPath:nil :iconOffset :iconSize ];
            
            UIImage *image = [sprite getSprite:[UIImage imageNamed:@"sprites6"]];
            UIImage *smallerImage = [UIImage imageWithCGImage:image.CGImage scale:1.5 orientation:image.imageOrientation];
            annotationView.image = smallerImage;
        }
        else
        {
            annotationView.annotation = annotation;
        }
        
        return annotationView;
    }
    
    return nil;
}

-(NSArray *)getRouteStopAnnotations:(R2RRoute *)route
{
    NSMutableArray *annotations = [[NSMutableArray alloc] init];
    
    for (R2RStop *stop in route.stops)
    {
        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(stop.pos.lat, stop.pos.lng);
        R2RStopAnnotation *annotation = [[R2RStopAnnotation alloc] initWithName:stop.name kind:stop.kind coordinate:coord];
        
        [annotations addObject:annotation];
    }
    
    return annotations;
}

-(NSArray *) getRouteHopAnnotations:(R2RRoute *)route
{
    NSMutableArray *hopAnnotations = [[NSMutableArray alloc] init];
    
    for (id segment in route.segments)
    {
        if([segment isKindOfClass:[R2RWalkDriveSegment class]])
        {
            [self getWalkDriveHopAnnotations:hopAnnotations :segment];
        }
        else if([segment isKindOfClass:[R2RTransitSegment class]])
        {
            [self getTransitHopAnnotations:hopAnnotations :segment];
        }
        else if([segment isKindOfClass:[R2RFlightSegment class]])
        {
            [self getFlightHopAnnotations:hopAnnotations :segment];
        }
    }
    
    return hopAnnotations;
}

-(void) getWalkDriveHopAnnotations:(NSMutableArray *) hopAnnotations:(R2RTransitSegment *)segment
{
    // no annotations
}

-(void) getTransitHopAnnotations:(NSMutableArray *)hopAnnotations:(R2RTransitSegment *)segment
{
    R2RTransitItinerary *itinerary = [segment.itineraries objectAtIndex:0];
    for (R2RTransitLeg *leg in itinerary.legs)
    {
        for (R2RTransitHop *hop in leg.hops)
        {
            BOOL isLastLeg = (leg == [itinerary.legs lastObject]);
            BOOL isLastHop = (hop == [leg.hops lastObject]);
            
            if (!isLastLeg && !isLastHop)
            {
                CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(hop.tPos.lat, hop.tPos.lng);
                R2RHopAnnotation *annotation = [[R2RHopAnnotation alloc] initWithName:hop.tName coordinate:coord];
                
                [hopAnnotations addObject:annotation];
            }
        }
    }
}

-(void) getFlightHopAnnotations:(NSMutableArray *) hopAnnotations:(R2RTransitSegment *)segment
{
    R2RFlightItinerary *itinerary = [segment.itineraries objectAtIndex:0];
    R2RFlightLeg *leg = [itinerary.legs objectAtIndex:0];
    
    for (R2RFlightHop *hop in leg.hops)
    {
        BOOL isLastHop = (hop == [leg.hops lastObject]);
        
        if (!isLastHop)
        {
            R2RAirport *airport = [self.dataStore getAirport:hop.tCode];
            if (airport == nil) continue;
            
            CLLocationCoordinate2D pos = CLLocationCoordinate2DMake(airport.pos.lat, airport.pos.lng);
            R2RHopAnnotation *annotation = [[R2RHopAnnotation alloc] initWithName:airport.name coordinate:pos];
            
            [hopAnnotations addObject:annotation];
        }
    }
}

-(void)filterAnnotations:(NSArray *)stops:(NSArray *)hops:(MKMapView *) mapView
{
    NSArray *placesToFilter = hops;
    
    float latDelta=mapView.region.span.latitudeDelta/20.0;
    float longDelta=mapView.region.span.longitudeDelta/20.0;
    
    NSMutableArray *placesToShow=[[NSMutableArray alloc] initWithCapacity:0];
    
    for (int i=0; i<[placesToFilter count]; i++)
    {
        R2RHopAnnotation *checkingLocation=[placesToFilter objectAtIndex:i];
        CLLocationDegrees latitude = checkingLocation.coordinate.latitude;
        CLLocationDegrees longitude = checkingLocation.coordinate.longitude;
        
        bool found=FALSE;
        
        for (R2RStopAnnotation *stopAnnotation in stops)
        {
            if(fabs(stopAnnotation.coordinate.latitude-latitude) < latDelta &&
               fabs(stopAnnotation.coordinate.longitude-longitude) <longDelta )
            {
                [mapView removeAnnotation:checkingLocation];
                found=TRUE;
                break;
            }
        }
        for (R2RHopAnnotation *hopAnnotation in placesToShow)
        {
            if(fabs(hopAnnotation.coordinate.latitude-latitude) < latDelta &&
               fabs(hopAnnotation.coordinate.longitude-longitude) <longDelta )
            {
                [mapView removeAnnotation:checkingLocation];
                found=TRUE;
                break;
            }
        }
        if (!found)
        {
            [placesToShow addObject:checkingLocation];
            [mapView addAnnotation:checkingLocation];
        }
    }
}

@end


@implementation R2RFlightPolyline

@end


@implementation R2RBusPolyline

@end


@implementation R2RTrainPolyline

@end


@implementation R2RFerryPolyline

@end


@implementation R2RWalkDrivePolyline

@end


@implementation R2RFlightPolylineView

-(id) initWithPolyline:(MKPolyline *)polyline
{
    self = [super initWithPolyline:polyline];
    if (self)
    {
        self.strokeColor = [R2RConstants getFlightLineColor];
        self.lineWidth = 4;
    }
    return self;
}

@end


@implementation R2RBusPolylineView

-(id) initWithPolyline:(MKPolyline *)polyline
{
    self = [super initWithPolyline:polyline];
    if (self)
    {
        self.strokeColor = [R2RConstants getBusLineColor];
        self.lineWidth = 4;
    }
    return self;
}

@end


@implementation R2RTrainPolylineView

-(id) initWithPolyline:(MKPolyline *)polyline
{
    self = [super initWithPolyline:polyline];
    if (self)
    {
        self.strokeColor = [R2RConstants getTrainLineColor];
        self.lineWidth = 4;
    }
    return self;
}

@end


@implementation R2RFerryPolylineView

-(id) initWithPolyline:(MKPolyline *)polyline
{
    self = [super initWithPolyline:polyline];
    if (self)
    {
        self.strokeColor = [R2RConstants getFerryLineColor];
        self.lineWidth = 4;
    }
    return self;
}

@end


@implementation R2RWalkDrivePolylineView

-(id) initWithPolyline:(MKPolyline *)polyline
{
    self = [super initWithPolyline:polyline];
    if (self)
    {
        self.strokeColor = [R2RConstants getWalkDriveLineColor];
        self.lineWidth = 4;
    }
    return self;
}

@end
