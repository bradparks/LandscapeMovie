//
//  AsyncURLDownloader.h
//
//  Created by Moses DeJong on 4/20/10.
//  Placed in the public domain.
//
// This class acts as a wrapper around the functionality
// provided by NSURLConnection. Downloads happen in a background
// thread and a Notification is provided when the download
// is finished. This class also supports canceling the
// async download operation.

#import <Foundation/Foundation.h>

// This event is delivered when the download is complete
extern NSString * const AsyncURLDownloadDidFinish;
// This event is delivered as the download progresses. If no
// download progress is made because no connectection can be made,
// then this event is not delivered.
extern NSString * const AsyncURLDownloadProgress;

@interface AsyncURLDownloader : NSObject {
  NSURL *m_url;
  NSData *m_postData;
  NSData *m_resultData;
  NSString *m_resultFilename;  
  int m_httpStatusCode;
  NSDictionary *m_requestHeaders;
  NSDictionary *m_responseHeaders;
  NSError *m_error;
  NSTimeInterval m_timeoutInterval;
  NSObject *m_connectionDelegate;
  NSURLConnection *m_connection;
  BOOL m_started;
  BOOL m_connected;
  BOOL m_downloaded;
}

@property (nonatomic, retain) NSURL *url;
@property (nonatomic, copy) NSData *postData;
@property (nonatomic, copy) NSData *resultData;
// A typical usage is to initiate a download and then wait until AsyncURLDownloadDidFinish is delivered.
// But, if a large file needs to be downloaded, then all the system memory could get used up by the
// download buffer. This can be addressed by setting the resultFilename property, so that download
// results will be read and saved to a file incrementally.
@property (nonatomic, copy) NSString *resultFilename;
@property (nonatomic, assign) int httpStatusCode;
@property (nonatomic, copy) NSDictionary *requestHeaders;
@property (nonatomic, copy) NSDictionary *responseHeaders;
@property (nonatomic, retain) NSError *error;
@property (nonatomic, assign) NSTimeInterval timeoutInterval;
@property (nonatomic, retain) NSObject *connectionDelegate;
@property (nonatomic, retain) NSURLConnection *connection;
@property (nonatomic, assign) BOOL started; // TRUE once startDownload has been invoked
@property (nonatomic, assign) BOOL connected; // TRUE once network connection has been made and downloading starts
@property (nonatomic, readonly) BOOL downloading; // TRUE after connection has been made, becomes FALSE when connection is closed
@property (nonatomic, assign) BOOL downloaded; // TRUE after connection has been made and downloading is complete

// Static constructor

+ (AsyncURLDownloader*) asyncURLDownloader;

// Static constructor that also saves the url but does not start download

+ (AsyncURLDownloader*) asyncURLDownloaderWithURL:(NSURL*)url;

// Starts download operation, should be invoked *after* notification
// have been defined for this object.

- (void) startDownload;

// Cancel download in progress

- (void) cancelDownload;

// Util method to save the contents of a NSString* encoded as utf8
// in the postData field.

- (void) setPostDataWithString:(NSString*)postDataString;

// Util method to return the contents of resultData (encoded as utf8) as a NSString*

- (NSString*) resultDataAsString;

@end
