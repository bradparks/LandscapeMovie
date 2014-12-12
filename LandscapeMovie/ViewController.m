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

#include "AsyncURLDownloader.h"

@interface ViewController ()

@property (nonatomic, retain) MPMoviePlayerController *moviePlayerController;

// Array of AsyncURLDownloader objects

@property (nonatomic, retain) NSMutableArray *asyncDownloaders;

// Table of download progress on a per file basis

@property (nonatomic, retain) NSMutableDictionary *asyncDownloaderProgress;

// Int percent done value, this is useful so that a percent done calculation
// need not update the GUI with the same value over and over as a result of
// multiple downloads being processed.

@property (nonatomic, assign) int percentDoneReported;

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
  
  NSAssert(moviePlayerController, @"moviePlayerController is nil");
  
  self.moviePlayerController = moviePlayerController;
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(moviePlaybackComplete:)
                                               name:MPMoviePlayerPlaybackDidFinishNotification
                                             object:moviePlayerController];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieDidExitFullscreen:)
                                               name:MPMoviePlayerDidExitFullscreenNotification
                                             object:moviePlayerController];
  
  CGRect frame = self.view.frame;
  
  NSLog(@"set movie width x height to %d x %d", (int)frame.size.width, (int)frame.size.height);
  
  [moviePlayerController.view setFrame:frame];
  
  [self.launchButton removeFromSuperview];
  
  [self.view addSubview:moviePlayerController.view];
  moviePlayerController.fullscreen = YES;
  
  moviePlayerController.scalingMode = MPMovieScalingModeFill;
  
  //[moviePlayerController prepareToPlay];
  
  [moviePlayerController play];
}

- (void)moviePlaybackComplete:(NSNotification *)notification
{
  MPMoviePlayerController *moviePlayerController = [notification object];
  
  [moviePlayerController stop];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MPMoviePlayerPlaybackDidFinishNotification
                                                object:moviePlayerController];
  
  [moviePlayerController.view removeFromSuperview];
  
  self.moviePlayerController = nil;
  
  CGRect frame = self.view.frame;
  UIImageView *imageView = [[UIImageView alloc] initWithFrame:frame];
  UIImage *theEndImage = [UIImage imageNamed:@"TheEnd.jpg"];
  NSAssert(theEndImage, @"theEndImage");
  imageView.image = theEndImage;
  [self.view addSubview:imageView];
}

// User pressed "Done" button

- (void)movieDidExitFullscreen:(NSNotification *)notification
{
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MPMoviePlayerDidExitFullscreenNotification
                                                object:self.moviePlayerController];
  
  [self moviePlaybackComplete:notification];
}

// Kick off movie download by checking the device screen size and choosing to download the right video

- (void)startMovieDownload
{
  NSString *entryName;
  
  if ([self isIpad]) {
    if ([self isRetinaDisplay]) {
      entryName   = @"Luna_1080p.mp4";
    } else {
      entryName   = @"Luna_720p.mp4";
    }
  } else {
    entryName   = @"Luna_480p.mp4";
  }
  
  if ([self.class doesTmpFileExist:entryName]) {
    NSString *tmpDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:entryName];
    
    NSLog(@"using cached video at %@", tmpDirPath);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
      [self playMovie:tmpDirPath];
    });
    
    return;
  }


  NSString *servicePrefix;

  const BOOL useDevDeploy = FALSE;
  
  if (useDevDeploy) {
    // Deployed locally via:
    // goapp serve
    servicePrefix = @"http://localhost:8080";
  } else {
    // Deployed to GAE via:
    // goapp deploy -oauth
    servicePrefix = @"http://sinuous-vortex-786.appspot.com";
  }
  
  // Outgoing Bandwidth : 1.12 of 1 GB
  // 503 Over Quota
  
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
  // Parse Json and then download each segment listed in the download,
  // if GAE is down (or you have hit the free download quota) then
  // this first download will fail.

  if (jsonData == nil) {
    NSString *msgStr = [NSString stringWithFormat:@"JSON download failed"];
    
    NSLog(@"%@", msgStr);
    
    UIAlertView *message = [[UIAlertView alloc] initWithTitle:@"Network Error"
                                                      message:msgStr
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
    
    [message show];
    
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
  
  // Kick off download for each chunk in a different GCD threads
  
  self.asyncDownloaders = [NSMutableArray array];
  
  for (NSDictionary *chunkEntry in chunkArr) {
    NSString *urlAndProtocolStr = [chunkEntry objectForKey:@"ChunkName"];
    NSString *chunkFilename = [urlAndProtocolStr lastPathComponent];
    [chunkFilenameArr addObject:chunkFilename];
    
    if ([self.class doesTmpFileExist:chunkFilename] == FALSE) {
      NSURL *url = [NSURL URLWithString:urlAndProtocolStr];
      
      AsyncURLDownloader *asyncURLDownloader = [AsyncURLDownloader asyncURLDownloaderWithURL:url];
      
      // Write to tmp/Chunk.gz.part and then rename to Chunk.gz when complete
      
      NSString *tmpDir = NSTemporaryDirectory();
      
      //NSString *tmpPath = [tmpDir stringByAppendingPathComponent:chunkFilename];
      
      NSString *tmpPartPath = [NSString stringWithFormat:@"%@.part", [tmpDir stringByAppendingPathComponent:chunkFilename]];
      
      asyncURLDownloader.timeoutInterval = 60 * 3; // longer than default timeout of 60 seconds
      
      asyncURLDownloader.resultFilename = tmpPartPath;
      
      NSLog(@"created async downloader for url %@", url);
      
      [self.asyncDownloaders addObject:asyncURLDownloader];

      NSString *sizeNum = [chunkEntry objectForKey:@"CompressedLength"];
      int size = [sizeNum intValue];
      
      [self updateDownloadedTableForDownloadFile:chunkFilename size:size];
      
      // Register for download progress notification
      
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(asyncURLDownloaderProgressNotification:)
                                                   name:AsyncURLDownloadProgress
                                                 object:asyncURLDownloader];
      
      // Register for notification when URL download is finished
      
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(asyncURLDownloaderDidFinishNotification:)
                                                   name:AsyncURLDownloadDidFinish
                                                 object:asyncURLDownloader];
    } else {
      // Chunk file already exists in tmp dir
      
      NSString *chunkFilepath = [NSTemporaryDirectory() stringByAppendingPathComponent:chunkFilename];
      
      [self updateDownloadedTableForCachedFile:chunkFilepath];
    }
  }

  [self activateDownloaders];
  
  // FIXME: this would be better done as a check on each downloader to see if completed
  
  // Create another threaded job that will wait until all downloads are completed
  
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    [self waitForAndJoinChunks:chunkFilenameArr entryName:entryName];
  });

}

// FIXME: look into background transfer service
// http://www.appcoda.com/background-transfer-service-ios7/

// This method is invoked when a download state changes or at the start of a download
// in order to activate 4 downloaders at any one time but no more than 4.

- (void) activateDownloaders
{
  int numDownloading = 0;
  
  // FIXME: NSURLSessionConfiguration.HTTPMaximumConnectionsPerHost check in iOS 7 ?
  
  const int maxDownloaders = 4;
  
  for (AsyncURLDownloader *asyncURLDownloader in self.asyncDownloaders) {
    if (asyncURLDownloader.started && asyncURLDownloader.downloading) {
      numDownloading++;
    }
  }
  
  NSLog(@"active downloaders %d", numDownloading);
  
  NSAssert(numDownloading <= maxDownloaders, @"maxDownloaders");

  int activate = maxDownloaders - numDownloading;
  
  int activated = 0;
  
  for (AsyncURLDownloader *asyncURLDownloader in self.asyncDownloaders) {
    if (activate > 0 && !asyncURLDownloader.started) {
      activate--;
      activated++;
      
      [asyncURLDownloader startDownload];
    }
  }
  
  NSLog(@"activated %d downloaders", activated);
}

// Invoked when ChunkN.gz file has been fully downloaded

- (void) asyncURLDownloaderDidFinishNotification:(NSNotification*)notification
{
  AsyncURLDownloader *asyncURLDownloader = [notification object];
  
  NSAssert(asyncURLDownloader != nil, @"asyncURLDownloader is nil");
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AsyncURLDownloadProgress object:asyncURLDownloader];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AsyncURLDownloadDidFinish object:asyncURLDownloader];
  
  int httpStatusCode = asyncURLDownloader.httpStatusCode;
  NSAssert(httpStatusCode > 0, @"httpStatusCode is invalid");
  
  if (httpStatusCode == 200) {
    NSString *partFilename = asyncURLDownloader.resultFilename;
    
    NSAssert([partFilename hasSuffix:@".part"], @"invalid part filename");
    
    NSString *gzFilename = [partFilename stringByDeletingPathExtension];
    
    [self finishedChunkDownload:gzFilename partFilepath:partFilename];
  } else {
    // FIXME: Show dialog with HTTP error status code and possible reason
    
//    NSAssert(FALSE, @"non 200 HTTP STATUS code %d", httpStatusCode);
    
    NSString *msgStr = [NSString stringWithFormat:@"HTTP status code %d : download canceled", httpStatusCode];
    
    NSLog(@"%@", msgStr);
    
    UIAlertView *message = [[UIAlertView alloc] initWithTitle:@"Network Error"
                                                      message:msgStr
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
    
    [message show];
  }
  return;
}

- (void)finishedChunkDownload:(NSString*)gzFilename partFilepath:(NSString*)partFilename
{
  if (TRUE) {
    NSData *mappedData = [NSData dataWithContentsOfMappedFile:partFilename];
    NSLog(@"finishedChunkDownload %9d bytes for seg %@", (int)mappedData.length, [gzFilename lastPathComponent]);
  }
  
  // Rename file to final result filename
  
  BOOL worked;
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:gzFilename]) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:gzFilename error:nil];
    NSAssert(worked, @"removeItemAtPath");
  }
  
  worked = [[NSFileManager defaultManager] moveItemAtPath:partFilename toPath:gzFilename error:nil];
  NSAssert(worked, @"rename from %@ to %@ failed", partFilename, gzFilename);

  [self activateDownloaders];
}

+ (BOOL) doesTmpFileExist:(NSString*)chunkFilename
{
  NSString *tmpDirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:chunkFilename];
  return [[NSFileManager defaultManager] fileExistsAtPath:tmpDirPath];
}

// Invoked on download progress (AsyncURLDownloadProgress)

- (void) asyncURLDownloaderProgressNotification:(NSNotification*)notification
{
  AsyncURLDownloader *downloader = notification.object;
  
  // DOWNLOADEDNUMBYTES -> int number of bytes downloaded
  // CONTENTNUMBYTES    -> int number of bytes to be downloaded via Content-Length HTTP header (cannot be relied on)

  NSNumber *downloadedNumBytesNum = [[notification userInfo] objectForKey:@"DOWNLOADEDNUMBYTES"];
  //NSNumber *contentNumBytesNum = [[notification userInfo] objectForKey:@"CONTENTNUMBYTES"];
  
  NSAssert(downloadedNumBytesNum, @"DOWNLOADEDNUMBYTES");
  //NSAssert(contentNumBytesNum, @"CONTENTNUMBYTES");
  
  NSString *filePath = downloader.resultFilename;
  
  NSString *fileTail = [filePath lastPathComponent];
  
  // Foo.gz.part -> Foo.gz
  
  fileTail = [fileTail stringByReplacingOccurrencesOfString:@".gz.part" withString:@".gz"];
  
  NSMutableDictionary *mDict = self.asyncDownloaderProgress;
  NSAssert(mDict, @"asyncDownloaderProgress");
  
  NSArray *currentValues = [mDict objectForKey:fileTail];
  NSAssert(currentValues, @"values not initialized for key %@", fileTail);
  
  NSNumber *compressedNumBytesNum = currentValues[1];
  
  NSArray *newValues = @[downloadedNumBytesNum, compressedNumBytesNum];
  
  // Downloads num bytes can never be larger than the CompressedNumBytes
  
  NSAssert([downloadedNumBytesNum intValue] <= [compressedNumBytesNum intValue], @"downloadedNumBytesNum > compressedNumBytesNum : %d > %d", [downloadedNumBytesNum intValue], [compressedNumBytesNum intValue]);
  
  [mDict setObject:newValues forKey:fileTail];
  
  //NSLog(@"updated key %@ in progress table to %@", fileTail, newValues);
  
  [self updatePercentDone];
}

// Invoked for a chunk that will be downloaded. The size of the file to be downloaded
// must be known ahead of time in order for the download % done logic to work properly.

- (void) updateDownloadedTableForDownloadFile:(NSString*)chunkFilepath size:(int)size
{
  if (self.asyncDownloaderProgress == nil) {
    self.asyncDownloaderProgress = [NSMutableDictionary dictionary];
  }

  NSMutableDictionary *mDict = self.asyncDownloaderProgress;
  NSAssert(mDict, @"asyncDownloaderProgress");
  
  NSNumber *sizeNum = [NSNumber numberWithInt:size];
  
  NSArray *arr = @[@(0), sizeNum];
  
  NSString *fileTail = [chunkFilepath lastPathComponent];
  
  [mDict setObject:arr forKey:fileTail];
}

// Invoked in the case where a file was already completely downloaded and is sitting in the tmp
// dir. Update the percent done table to account for the fully downloaded file.

- (void) updateDownloadedTableForCachedFile:(NSString*)chunkFilepath
{
  if (self.asyncDownloaderProgress == nil) {
    self.asyncDownloaderProgress = [NSMutableDictionary dictionary];
  }
  
  NSMutableDictionary *mDict = self.asyncDownloaderProgress;
  NSAssert(mDict, @"asyncDownloaderProgress");
  
  NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:chunkFilepath error:nil];
  if (attrs == nil) {
    // File does not exist or can't be accessed
    NSAssert(FALSE, @"attributesOfItemAtPath failed for %@", chunkFilepath);
  }
  unsigned long long fileSize = [attrs fileSize];
  size_t fileSizeT = (size_t) fileSize;
  NSAssert(fileSize == fileSizeT, @"assignment from unsigned long long to size_t lost bits");
  
  NSNumber *intNum = [NSNumber numberWithInt:(int)fileSize];
  
  NSArray *arr = @[intNum, intNum];
  
  NSString *fileTail = [chunkFilepath lastPathComponent];
  
  [mDict setObject:arr forKey:fileTail];
}

- (void) updatePercentDone
{
  const BOOL debugPercentDone = FALSE;
  
  if (debugPercentDone) {
    NSLog(@"updatePercentDone");
  }
  
  int totalBytesDownloaded = 0;
  int totalBytesToDownload = 0;
  
  NSAssert(self.asyncDownloaderProgress, @"asyncDownloaderProgress");
  
  for (NSString *chunkFilename in [self.asyncDownloaderProgress allKeys]) {
    NSArray *arr = [self.asyncDownloaderProgress objectForKey:chunkFilename];
    NSAssert(arr, @"no asyncDownloaderProgress for file %@", chunkFilename);
    
    NSNumber *downloadedNumBytesNum = arr[0];
    NSNumber *contentNumBytesNum = arr[1];
    
    totalBytesDownloaded += [downloadedNumBytesNum intValue];
    totalBytesToDownload += [contentNumBytesNum intValue];

    if (debugPercentDone) {
      NSLog(@"add progress num bytes %d of %d", [downloadedNumBytesNum intValue], [contentNumBytesNum intValue]);
    }
  }
  
  float percentDoneNormalized = ((float)totalBytesDownloaded) / totalBytesToDownload;
  
  int percentDoneInt = (int)round(percentDoneNormalized*100.0f);
  
  if (percentDoneInt == 0) {
    percentDoneInt = 1;
  }
  
  if (self.percentDoneReported == percentDoneInt) {
    // Already update the display with this % done numeric value
    return;
  }
  
//  if (percentDoneInt > 1 && percentDoneInt < 99 && self.percentDoneReported+1 == percentDoneInt) {
//    // If not 1% or 99% or 100% then skip redrawing until at least 2% delta
//    return;
//  }

  self.percentDoneReported = percentDoneInt;
  
  NSString *percentDoneStr = [NSString stringWithFormat:@"%3d", percentDoneInt];
  
  if (debugPercentDone) {
    NSLog(@"percentDoneStr %@", percentDoneStr);
  }
  
  NSString *percentDoneTitle = [NSString stringWithFormat:@"Loading ... %@%%", percentDoneStr];
  
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
    [self.launchButton setTitle:percentDoneTitle forState:UIControlStateNormal];
  });
}

- (void)waitForAndJoinChunks:(NSArray*)chunkFilenameArr entryName:(NSString*)entryName
{
  const BOOL debugWait = FALSE;
  
  if (debugWait) {
  NSLog(@"waitForAndJoinChunks %d files for entryName %@", (int)chunkFilenameArr.count, entryName);
  }
  
  NSAssert(chunkFilenameArr, @"chunkFilenameArr is nil");
  NSAssert(chunkFilenameArr.count > 0, @"chunkFilenameArr.count is zero");
  
  // Defer unless all files exist at this point
  
  BOOL allFileExist = TRUE;
  
  for (NSString *chunkFilename in chunkFilenameArr) {
    if ([self.class doesTmpFileExist:chunkFilename] == FALSE) {
      allFileExist = FALSE;
    }
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
    
    if (TRUE) {
      NSData *mappedData = [NSData dataWithContentsOfMappedFile:tmpInputPath];
      NSLog(@"chunk %@ -> %d bytes", [tmpInputPath lastPathComponent], (int)mappedData.length);
    }
    
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
          char * msg = (char*) gzerror(inGZFile, &err);
          if (err != 0) {
            NSAssert(TRUE, @"cannot read full buffer via gzread: %d -> %s", err, msg);
          }
        }
      }
    }
    
    gzclose(inGZFile);
  }

  fclose(outMp4File);
  
  NSLog(@"wrote %@", tmpOutputPath);
  
  if (TRUE) {
    // Remove chunks after writing final output
    
    for (NSString *inGZPathStr in chunkFilenameArr) {
      NSLog(@"rm %@", inGZPathStr);
      
      NSError *error;
      BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:inGZPathStr error:&error];
      if (!worked) {
        NSLog(@"could not delete %@", inGZPathStr);
      }
    }
    
  }
  
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    [self playMovie:tmpOutputPath];
  });
}

// Return TRUE on iPad device, if FALSE then iPhone device.

- (BOOL) isIpad
{
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// Return TRUE for a 2x or 3x scale display on iPhone or iPad devices.
// This function returns FALSE on original iPhone 3 or iPad 1 or 2 devices.

- (BOOL) isRetinaDisplay
{
  if ([[UIScreen mainScreen] respondsToSelector:@selector(displayLinkWithTarget:selector:)] &&
      ([UIScreen mainScreen].scale == 2.0)) {
    // Retina display
    return TRUE;
  } else {
    // non-Retina display
    return FALSE;
  }
}

@end
