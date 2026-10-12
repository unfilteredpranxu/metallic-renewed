#import "utils.h"
#import "ImageCropperViewController.h"
#import "BackgroundManager.h"

@interface ImageCropperViewController ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *cropOverlayView;
@property (nonatomic, assign) CGRect cropRect;
@property (nonatomic, assign) CGFloat scale;
@end

@implementation ImageCropperViewController

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        _sourceImage = image;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Adapt to the custom launcher background: make this view controller transparent so the global wallpaper shows through.
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];

    self.title = localize(@"i18n_str_319", nil);
    self.view.backgroundColor = [UIColor blackColor];
    
    // Add navigation-bar buttons.
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    self.navigationItem.leftBarButtonItem = cancelButton;
    
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem = doneButton;
    
    // Calculate the scale and crop region.
    [self calculateCropRect];
    
    // Create the image view.
    self.imageView = [[UIImageView alloc] init];
    self.imageView.image = self.sourceImage;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = self.cropRect;
    [self.view addSubview:self.imageView];
    
    // Create the crop overlay.
    [self createCropOverlay];
    
    // Add gesture recognizers.
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.imageView addGestureRecognizer:panGesture];
    self.imageView.userInteractionEnabled = YES;
    
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.imageView addGestureRecognizer:pinchGesture];

    // Listen for background UI-effect changes and reapply transparency when the user switches
    // background effects (translucent/frosted glass).
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reapplyBackgroundEffect)
                                                 name:@"BackgroundUIEffectChanged"
                                               object:nil];
}

/// Reapply transparency when the background effect changes (triggered by the BackgroundUIEffectChanged notification).
- (void)reapplyBackgroundEffect {
    [[BackgroundManager sharedManager] makeViewControllerTransparent:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)calculateCropRect {
    CGSize imageSize = self.sourceImage.size;
    CGSize viewSize = self.view.bounds.size;
    
    // Calculate the square crop region.
    CGFloat squareSize = MIN(viewSize.width, viewSize.height) * 0.8;
    CGFloat x = (viewSize.width - squareSize) / 2;
    CGFloat y = (viewSize.height - squareSize) / 2;
    self.cropRect = CGRectMake(x, y, squareSize, squareSize);
    
    // Calculate the initial scale.
    CGFloat scaleX = squareSize / imageSize.width;
    CGFloat scaleY = squareSize / imageSize.height;
    self.scale = MAX(scaleX, scaleY);
}

- (void)createCropOverlay {
    // Create the translucent overlay.
    UIView *overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    overlayView.userInteractionEnabled = NO;
    [self.view insertSubview:overlayView atIndex:0];
    
    // Create the crop frame.
    self.cropOverlayView = [[UIView alloc] initWithFrame:self.cropRect];
    self.cropOverlayView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.cropOverlayView.layer.borderWidth = 2.0;
    self.cropOverlayView.backgroundColor = [UIColor clearColor];
    self.cropOverlayView.userInteractionEnabled = NO;
    [self.view addSubview:self.cropOverlayView];
    
    // Create the transparent area inside the crop frame.
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.view.bounds];
    UIBezierPath *cropPath = [UIBezierPath bezierPathWithRect:self.cropRect];
    [path appendPath:cropPath];
    path.usesEvenOddFillRule = YES;
    maskLayer.path = path.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;
    overlayView.layer.mask = maskLayer;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.imageView];
    [gesture setTranslation:CGPointZero inView:self.imageView];
    
    CGPoint newCenter = CGPointMake(self.imageView.center.x + translation.x, self.imageView.center.y + translation.y);
    self.imageView.center = newCenter;
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        self.imageView.transform = CGAffineTransformScale(self.imageView.transform, gesture.scale, gesture.scale);
        gesture.scale = 1.0;
    }
}

- (void)cancelTapped {
    if (self.completionHandler) {
        self.completionHandler(nil);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)doneTapped {
    UIImage *croppedImage = [self cropImage];
    if (self.completionHandler) {
        self.completionHandler(croppedImage);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (UIImage *)cropImage {
    // Convert crop-frame coordinates to image coordinates.
    CGRect cropBounds = self.cropOverlayView.frame;
    CGRect imageFrame = self.imageView.frame;
    
    CGFloat scaleX = self.sourceImage.size.width / imageFrame.size.width;
    CGFloat scaleY = self.sourceImage.size.height / imageFrame.size.height;
    
    CGRect cropRectInImage = CGRectMake(
        (cropBounds.origin.x - imageFrame.origin.x) * scaleX,
        (cropBounds.origin.y - imageFrame.origin.y) * scaleY,
        cropBounds.size.width * scaleX,
        cropBounds.size.height * scaleY
    );
    
    // Ensure the crop region stays within the image bounds.
    cropRectInImage = CGRectIntersection(cropRectInImage, CGRectMake(0, 0, self.sourceImage.size.width, self.sourceImage.size.height));
    
    // Create a square image with a black background.
    UIGraphicsBeginImageContextWithOptions(cropRectInImage.size, YES, self.sourceImage.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Fill the background with black.
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, cropRectInImage.size.width, cropRectInImage.size.height));
    
    // Draw the cropped image over the black background.
    CGRect drawRect = CGRectMake(0, 0, cropRectInImage.size.width, cropRectInImage.size.height);
    [self.sourceImage drawInRect:drawRect blendMode:kCGBlendModeNormal alpha:1.0];
    
    UIImage *croppedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return croppedImage;
}

@end