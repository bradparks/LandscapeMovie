//
//  ViewController.m
//  LandscapeMovie
//
//  Created by Mo DeJong on 12/9/14.
//  Copyright (c) 2014 helpurock software. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  
  NSAssert(self.launchButton, @"launchButton");
  
  //UIWindow *window = self.view.window;
  
  UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
  
  CGRect frame = window.frame;
  
  self.view.frame = frame;
  
  NSLog(@"resize view frame to %d x %d", (int)self.view.frame.size.width, (int)self.view.frame.size.height);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
{
  if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
    return YES;
  } else {
    return NO;
  }
}

- (BOOL)shouldAutorotate {
  
  UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
  
  if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
    return YES;
  } else {
    return NO;
  }
}

@end
