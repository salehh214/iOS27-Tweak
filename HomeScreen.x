%hook SBDockView
- (void)layoutSubviews {
    %orig;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if (bgView) {
        bgView.hidden = YES;
        bgView.alpha = 0.0;
    }

    // Dock Style: 0 = Floating Glass, 1 = Classic Full-Width Glass, 2 = iPad Compact Pill, 3 = Dark Smoked Glass, 4 = Transparent
    NSInteger dockStyle = iOS27IntPref(@"kDockStyle", 0);

    UIView *glassDock = [self viewWithTag:27001];
    if (dockStyle == 4) {
        if (glassDock) glassDock.hidden = YES;
        return;
    }

    if (!glassDock) {
        glassDock = [[UIView alloc] initWithFrame:CGRectZero];
        glassDock.tag = 27001;
        glassDock.userInteractionEnabled = NO;
        [self insertSubview:glassDock atIndex:0];
    }
    glassDock.hidden = NO;

    if (dockStyle == 1) {
        // Classic Full-Width Glass (Bottom edge-to-edge)
        glassDock.frame = self.bounds;
        ApplyFakeGlass(glassDock, 22.0, gGlassAlpha);
        glassDock.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (dockStyle == 2) {
        // iPad Compact Floating Pill
        glassDock.frame = CGRectInset(self.bounds, 18.0, 8.0);
        ApplyFakeGlass(glassDock, 34.0, gGlassAlpha);
        glassDock.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (dockStyle == 3) {
        // Dark Smoked Floating Glass
        glassDock.frame = CGRectInset(self.bounds, 10.0, 6.0);
        ApplyFakeGlass(glassDock, 30.0, MAX(gGlassAlpha, 0.52));
        glassDock.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:0.58];
        glassDock.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else {
        // Default: iOS 27 Floating Glass
        glassDock.frame = CGRectInset(self.bounds, 10.0, 6.0);
        ApplyFakeGlass(glassDock, 30.0, gGlassAlpha);
        glassDock.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
}
%end
