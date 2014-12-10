//
//  ViewController.m
//  LandscapeMovie
//
//  Created by Mo DeJong on 12/9/14.
//  Copyright (c) 2014 helpurock software. All rights reserved.
//

#import "ViewController.h"

#import <MediaPlayer/MediaPlayer.h>

#include <zlib.h>

@interface ViewController ()

@property (nonatomic, retain) MPMoviePlayerController *moviePlayerController;

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
  
  [self startMovieDownload];
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

// This method is invoked when network loading of the movie is completed

- (void) playMovie:(NSString*)localMoviePath
{
  NSURL    *fileURL    =   [NSURL fileURLWithPath:localMoviePath];
  MPMoviePlayerController *moviePlayerController = [[MPMoviePlayerController alloc] initWithContentURL:fileURL];
  
  self.moviePlayerController = moviePlayerController;
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(moviePlaybackComplete:)
                                               name:MPMoviePlayerPlaybackDidFinishNotification
                                             object:moviePlayerController];
  
  CGRect frame = self.view.frame;
  
  [moviePlayerController.view setFrame:frame];
  
  [self.view addSubview:moviePlayerController.view];
  moviePlayerController.fullscreen = YES;
  
  moviePlayerController.scalingMode = MPMovieScalingModeFill;
  
  [moviePlayerController prepareToPlay];
  
  [moviePlayerController play];
}

- (void)moviePlaybackComplete:(NSNotification *)notification
{
  MPMoviePlayerController *moviePlayerController = [notification object];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MPMoviePlayerPlaybackDidFinishNotification
                                                object:moviePlayerController];
  
  [moviePlayerController.view removeFromSuperview];
  
  self.moviePlayerController = nil;
}

- (void)startMovieDownload
{
  //NSString *entryName   = @"Luna_480p.mp4";
  //NSString *entryName   = @"Luna_720p.mp4";
  NSString *entryName   = @"Luna_1080p.mp4";
  
  if ([self.class doesTmpFileExist:entryName]) {
    NSString *tmpDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:entryName];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      [self playMovie:tmpDirPath];
    });
    
    return;
  }
  
  const BOOL useDevDeploy = FALSE;

  NSString *servicePrefix;
  
  if (useDevDeploy) {
    // Deployed locally via:
    // goapp serve
    servicePrefix = @"http://localhost:8080";
  } else {
    // Deployed to GAE via:
    // goapp deploy -oauth
    servicePrefix = @"http://sinuous-vortex-786.appspot.com";
  }
  
  NSString *segmentsJsonURL   = [NSString stringWithFormat:@"%@/%@", servicePrefix, entryName];
  NSURL *url = [NSURL URLWithString:segmentsJsonURL];
  NSAssert(url, @"url");
  
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    NSLog(@"downloading movie url: %@", url);
    NSData *jsonData = [NSData dataWithContentsOfURL:url];
    [self finishedChunksDownload:jsonData entryName:entryName];
  });
}

- (void)finishedChunksDownload:(NSData*)jsonData entryName:(NSString*)entryName
{
  // Parse Json and then download each segment listed in the download

  if (jsonData == nil) {
    NSLog(@"JSON url download failed");
    return;
  }
  
  NSError *localError = nil;
  
  NSDictionary *parsedObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&localError];
  
  if (localError != nil) {
    NSLog(@"JSON url error: %@", localError);
    return;
  }

  NSLog(@"JSON: %@", parsedObject);
  
  NSArray *chunkArr = [parsedObject valueForKey:entryName];
  NSAssert(chunkArr, @"chunks not found for entryName %@", entryName);
  
  NSMutableArray *chunkFilenameArr = [NSMutableArray array];
  
  // Kick off download for each chunk in a different thread
  
  for (NSString *urlStr in chunkArr) {

    NSString *chunkFilename = [urlStr lastPathComponent];
    [chunkFilenameArr addObject:chunkFilename];
    
    if ([self.class doesTmpFileExist:chunkFilename] == FALSE) {
      
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSString *urlAndProtocolStr = [NSString stringWithFormat:@"http://%@", urlStr];
        NSURL *url = [NSURL URLWithString:urlAndProtocolStr];
        
        NSLog(@"start download %@", url);
        
        NSData *gzipData = [NSData dataWithContentsOfURL:url];
        [self finishedChunkDownload:gzipData segName:chunkFilename];
      });
      
    }
    
  }
  
  // Create another threaded job that will wait until all downloads are completed
  
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    [self waitForAndJoinChunks:chunkFilenameArr entryName:entryName];
  });
  
}

- (void)finishedChunkDownload:(NSData*)gzipData segName:(NSString*)segName
{
  NSLog(@"finishedChunkDownload %9d bytes for seg %@", (int)gzipData.length, segName);
  
  if (gzipData == nil) {
    NSAssert(FALSE, @"download failed for %@", segName);
  }

  if (gzipData.length == 0) {
    NSAssert(FALSE, @"download length must not be zero for %@", segName);
  }
  
  NSString *tmpDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:segName];
  
  BOOL worked = [gzipData writeToFile:tmpDirPath atomically:TRUE];
  
  NSAssert(worked, @"write for %@ failed", segName);
}

+ (BOOL) doesTmpFileExist:(NSString*)chunkFilename
{
  NSString *tmpDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:chunkFilename];
  return [[NSFileManager defaultManager] fileExistsAtPath:tmpDirPath];
}

- (void)waitForAndJoinChunks:(NSArray*)chunkFilenameArr entryName:(NSString*)entryName
{
  const BOOL debugWait = FALSE;
  
  if (debugWait) {
  NSLog(@"waitForAndJoinChunks %d files for entryName %@", (int)chunkFilenameArr.count, entryName);
  }
  
  // Defer unless all files exist at this point
  
  BOOL allFileExist = TRUE;
  
  float percentDoneNormalized = 0.0f;
  
  for (NSString *chunkFilename in chunkFilenameArr) {
    if ([self.class doesTmpFileExist:chunkFilename] == FALSE) {
      allFileExist = FALSE;
    } else {
      percentDoneNormalized += (100.0f / chunkFilenameArr.count) / 100.0f;
    }
  }

  int percentDoneInt = (int)round(percentDoneNormalized*100.0f);
  
  if (percentDoneInt == 0) {
    percentDoneInt = 1;
  }
  
  NSString *percentDoneStr = [NSString stringWithFormat:@"%3d", percentDoneInt];

  if (debugWait || 1) {
    NSLog(@"percentDoneStr %@", percentDoneStr);
  }
  
  NSString *percentDoneTitle = [NSString stringWithFormat:@"Loading ... %@%%", percentDoneStr];
  
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    [self.launchButton setTitle:percentDoneTitle forState:UIControlStateNormal];
  });
  
  if (debugWait || 1) {
    NSLog(@"percentDoneTitle %@", percentDoneTitle);
  }
  
  if (allFileExist) {
    // Join segments into one long gz file
    
    [self joinAllChunks:chunkFilenameArr entryName:entryName];
  } else {
    if (debugWait) {
    NSLog(@"waitForAndJoinSegments: all files not downloaded yet");
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [self waitForAndJoinChunks:chunkFilenameArr entryName:entryName];
      });
    });
  }
}

// After all downloads have completed this method is invoked to join to gz segments

- (void) joinAllChunks:(NSArray*)chunkFilenameArr entryName:(NSString*)entryName
{
  NSLog(@"joinAllChunks: all files downloaded");
 
  // Stream N files of data from the chunk files to uncompressed .mp4
  
  NSString *tmpOutputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:entryName];
  
  FILE *outMp4File = fopen((char*)[tmpOutputPath UTF8String], "w");
  NSAssert(outMp4File, @"cannot open output path for writing");
  
  gzFile * inGZFile;
  const int LENGTH = 0x1000 * 16; // 16 pages
  
  for (NSString *inGZPathStr in chunkFilenameArr) {
    NSString *tmpInputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:inGZPathStr];
    
    inGZFile = gzopen ((char*)[tmpInputPath UTF8String], "r");
    NSAssert(inGZFile, @"cannot open input path for reading");
    
    unsigned char buffer[LENGTH];
    int bytes_read;
    int bytes_written;
    int err;
    
    while (1) {
      bytes_read = gzread(inGZFile, buffer, LENGTH);
      
      if (bytes_read > 0) {
        bytes_written = (int) fwrite(buffer, 1, bytes_read, outMp4File);
        if (bytes_written != bytes_read) {
          NSAssert(bytes_written == bytes_read, @"bytes_written != bytes_read : %d != %d", bytes_written, bytes_read);
        }
      }
      
      if (bytes_read < LENGTH) {
        if (gzeof(inGZFile)) {
          break;
        } else {
          gzerror(inGZFile, & err);
          if (err) {
            NSAssert(inGZFile, @"cannot read full buffer via gzread");
          }
        }
      }
    }
    
    gzclose(inGZFile);
  }

  fclose(outMp4File);
  
  NSLog(@"wrote %@", tmpOutputPath);
  
  if (0) {
    // Remove chunks after writing final output
    
    for (NSString *inGZPathStr in chunkFilenameArr) {
      NSLog(@"rm %@", inGZPathStr);
      unlink((char*)[inGZPathStr UTF8String]);
    }
    
  }
  
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    [self playMovie:tmpOutputPath];
  });
}

@end
