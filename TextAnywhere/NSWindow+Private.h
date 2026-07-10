//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSWindow ()

@property (nonatomic, assign, setter=_setCornerRadius:) CGFloat _cornerRadius;

- (void)_layoutViewTree;

@end

NS_ASSUME_NONNULL_END
