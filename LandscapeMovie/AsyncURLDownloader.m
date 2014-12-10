//
//  AsyncURLDownloader.m
//
//  Created by Moses DeJong on 4/20/10.
//  Placed in the public domain.
//

#import <CFNetwork/CFNetwork.h>
#import "AsyncURLDownloader.h"

NSString * const AsyncURLDownloadDidFinish = @"AsyncURLDownloadDidFinish";
NSString * const AsyncURLDownloadProgress = @"AsyncURLDownloadProgress";
NSString * const AsyncURLDownloaderConnectionDelegateDidFinish = @"AsyncURLDownloaderConnectionDelegateDidFinish";
NSString * const AsyncURLDownloaderConnectionDelegateProgress = @"AsyncURLDownloaderConnectionDelegateProgress";

// Class AsyncURLDownloaderConnectionDelegate is needed because NSURLConnection
// has a really strange (but documented) behaviour of retaining the delegate.
// It says the reference will be dropped when the connection is released, but
// holding the connection in self creates a danger filled case of a circular
// ref loop. Create a small delegate object to deal with this safely.

@interface AsyncURLDownloaderConnectionDelegate : NSObject {
  int httpStatusCode;
  int contentLength;
  int downloadedBytes;
  NSMutableData *m_data;
  NSDictionary *m_responseHeaders;
  NSString *m_resultFilename;
}

@property (nonatomic, retain) NSMutableData *data;
@property (nonatomic, copy) NSDictionary *responseHeaders;
@property (nonatomic, copy) NSString *resultFilename;

+ (AsyncURLDownloaderConnectionDelegate*) asyncURLDownloaderConnectionDelegate;
@end

// Class AsyncURLDownloader

@implementation AsyncURLDownloader

@synthesize url = m_url;
@synthesize postData = m_postData;
@synthesize resultData = m_resultData;
@synthesize resultFilename = m_resultFilename;
@synthesize httpStatusCode = m_httpStatusCode;
@synthesize requestHeaders = m_requestHeaders;
@synthesize responseHeaders = m_responseHeaders;
@synthesize error = m_error;
@synthesize timeoutInterval = m_timeoutInterval;
@synthesize connection = m_connection;
@synthesize connectionDelegate = m_connectionDelegate;
@synthesize started = m_started;
@synthesize connected = m_connected;
@dynamic downloading;
@synthesize downloaded = m_downloaded;

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];  

  self.url = nil;
  self.postData = nil;
  self.resultData = nil;
  self.resultFilename = nil;
  //self.httpStatusCode = 0;
  self.requestHeaders = nil;
  self.responseHeaders = nil;
  self.error = nil;
  //self.timeoutInterval = 0.0;
  self.connection = nil;
  self.connectionDelegate = nil;
  //self.started = FALSE;
  //self.downloading = FALSE;
  //self.downloaded = FALSE;

#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

+ (AsyncURLDownloader*) asyncURLDownloader
{
  AsyncURLDownloader *obj = [[AsyncURLDownloader alloc] init];
#if __has_feature(objc_arc)
#else
  obj = [obj autorelease];
#endif // objc_arc
  obj.timeoutInterval = 60; // system default timeout
  return obj;
}

+ (AsyncURLDownloader*) asyncURLDownloaderWithURL:(NSURL*)url
{
  NSAssert(url != nil, @"url is nil");
  AsyncURLDownloader *obj = [AsyncURLDownloader asyncURLDownloader];
  if (obj == nil) {
    return nil;
  }
  obj.url = url;
  return obj;
}

- (void) startDownload
{
  NSAssert(self.started == FALSE, @"already started");

  // Use connectionDelegate to ensure that there is no circular reference loop from the connection
  // back to this object.
 
#if __has_feature(objc_arc)
#else
  int retainCountIn = self.retainCount;
#endif // objc_arc
  
  NSAssert(self.connectionDelegate == nil, @"already a connectionDelegate");
  AsyncURLDownloaderConnectionDelegate *delegate = [AsyncURLDownloaderConnectionDelegate asyncURLDownloaderConnectionDelegate];
  self.connectionDelegate = delegate;
  
  // If download filename is defined, then set the property on the delegate so that data
  // is incrementally written to a file in the web download thread.

  NSString *resultFilename = self.resultFilename;
  if (resultFilename != nil) {
    delegate.resultFilename = resultFilename;
    delegate.data = nil;

    // Truncate file contents to an empty file
    [[NSData data] writeToFile:resultFilename atomically:TRUE];
  }
  
  // Choose NSURLRequestReloadIgnoringLocalAndRemoteCacheData since there is no case
  // where we actually want local or gateway cached data.
  NSUInteger policy;

//  policy = NSURLRequestReloadIgnoringLocalCacheData;
  policy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    
  // Note that the connection automatically sends the header "Accept-Encoding" = "gzip"

  NSMutableURLRequest* mrequestObj = [NSMutableURLRequest requestWithURL:self.url];

  [mrequestObj setCachePolicy:policy];
  [mrequestObj setTimeoutInterval:self.timeoutInterval];
  
  // Set http header fields if given
  
  if (self.requestHeaders != nil) {
    for (NSString *key in [self.requestHeaders allKeys]) {
      NSString *value = [self.requestHeaders objectForKey:key];
      [mrequestObj setValue:value forHTTPHeaderField:key];
    }
  }
  
  // Request defaults to "GET"
  
  if (self.postData != nil) {
    [mrequestObj setHTTPMethod:@"POST"];
    [mrequestObj setHTTPBody:self.postData];
  }

  // Listen for Notifications from connectionDelegate
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(asyncURLDownloaderConnectionDelegateDidFinishNotification:)
                                               name:AsyncURLDownloaderConnectionDelegateDidFinish
                                             object:self.connectionDelegate];  

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(asyncURLDownloaderConnectionDelegateProgressNotification:)
                                               name:AsyncURLDownloaderConnectionDelegateProgress
                                             object:self.connectionDelegate];
  
  // Kick off download
  
  NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:mrequestObj delegate:self.connectionDelegate startImmediately:TRUE];

#if __has_feature(objc_arc)
#else
  connection = [connection autorelease];
#endif // objc_arc
  
  // Critical that we don't invoke [connection start] here, startImmediately:TRUE was passed above and invoking
  // start would lead to a very difficult to track down core dump!
  
  self.connection = connection;
  self.started = TRUE;

#if __has_feature(objc_arc)
#else
  int retainCountOut = self.retainCount;
  NSAssert(retainCountIn == retainCountOut, @"retainCount incremented in startDownload");
#endif // objc_arc
  
  return;
}

- (void) _releaseConnection
{
  self.connection = nil;
  self.connectionDelegate = nil;
}

- (void) cancelDownload
{
  if (!self.started) {
    return;
  }
  [self.connection cancel];
  [self _releaseConnection];
}

// Custom getter for downloading property

- (BOOL) downloading
{
  AsyncURLDownloaderConnectionDelegate *delegate = (AsyncURLDownloaderConnectionDelegate*) self.connectionDelegate;

  int numBytesDownloaded;
  if (delegate == nil || delegate.data == nil) {
    // If download was canceled then the delegate can be nil
    // If download is complete, then data can be set to nil in the delegate
    numBytesDownloaded = 0;
  } else {
    numBytesDownloaded = (int) [delegate.data length];
  }
  BOOL isDownloading = (numBytesDownloaded > 0);
  if (isDownloading) {
    // Avoid infinite loop by not calling self.connected
    // to query the state here!
    self->m_connected = TRUE;
    return TRUE;
  } else {
    return FALSE;
  }
}

// Query of connected property needs to check to see if we are currently downloading

- (BOOL) connected
{
  [self downloading];
  return self->m_connected;
}

- (void) asyncURLDownloaderConnectionDelegateProgressNotification:(NSNotification*)notification
{
  // If there is a race condition between canceling the download and the delivery of the
  // notification, then ignore the notification.
  
  if (!self.started || (self.connection == nil)) {
    return;
  }
  
  // Save results and translate notification name
  
  NSDictionary *userInfo = notification.userInfo;
  NSAssert(userInfo, @"userInfo is nil");

  self.connected = TRUE;
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AsyncURLDownloadProgress object:self userInfo:userInfo];
  
  return;  
}

- (void) asyncURLDownloaderConnectionDelegateDidFinishNotification:(NSNotification*)notification
{
  // If there is a race condition between canceling the download and the delivery of the
  // notification, then ignore the notification.
  
  if (!self.started || (self.connection == nil)) {
    return;
  }
  
  // Save results and translate notification name
  
  NSDictionary *userInfo = notification.userInfo;
  NSAssert(userInfo, @"userInfo is nil");

  self.httpStatusCode = [[userInfo objectForKey:@"HTTPSTATUS"] intValue];
  self.resultData = [userInfo objectForKey:@"DATA"];
  
  id responseHeadersObj = [userInfo objectForKey:@"RESPONSEHEADERS"];
  NSAssert(responseHeadersObj, @"RESPONSEHEADERS is nil");
  if (responseHeadersObj == [NSNull null]) {
    self.responseHeaders = nil;
  } else {
    self.responseHeaders = responseHeadersObj;    
  }
  
  id errorObj = [userInfo objectForKey:@"ERROR"];
  NSAssert(errorObj, @"ERROR is nil");
  if (errorObj == [NSNull null]) {
    self.error = nil;
  } else {
    self.error = errorObj;    
  }

  [[NSNotificationCenter defaultCenter] removeObserver:self name:AsyncURLDownloaderConnectionDelegateDidFinish object:self.connectionDelegate];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AsyncURLDownloaderConnectionDelegateProgress object:self.connectionDelegate];

  // Note that an extra ref to self must be held while AsyncURLDownloadDidFinish executes, to deal with the case where the final ref
  // to this objet is being dropped in the notification callback.
  
#if __has_feature(objc_arc)
  // FIXME: need to hold on to self here with ARC ?
#else
  [self retain];
#endif // objc_arc
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AsyncURLDownloadDidFinish object:self userInfo:userInfo];
  
  [self _releaseConnection];

  self.connected = TRUE;
  self.downloaded = TRUE;

#if __has_feature(objc_arc)
#else
  [self release];
#endif // objc_arc
  
  return;
}

- (void) setPostDataWithString:(NSString*)postDataStr {
  self.postData = [postDataStr dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString*) resultDataAsString {
  NSString *obj = [[NSString alloc] initWithData:self.resultData encoding:NSUTF8StringEncoding];
  
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

@end // Class AsyncURLDownloader



// Class AsyncURLDownloaderConnectionDelegate

@implementation AsyncURLDownloaderConnectionDelegate

@synthesize data = m_data;
@synthesize responseHeaders = m_responseHeaders;
@synthesize resultFilename = m_resultFilename;

+ (AsyncURLDownloaderConnectionDelegate*) asyncURLDownloaderConnectionDelegate
{
  AsyncURLDownloaderConnectionDelegate *obj = [[AsyncURLDownloaderConnectionDelegate alloc] init];
#if __has_feature(objc_arc)
#else
  obj = [obj autorelease];
#endif // objc_arc

  obj.data = [NSMutableData dataWithCapacity:4096];
  NSAssert(obj.data != nil, @"data can't be nil");
  obj->downloadedBytes = 0;
  return obj;
}

- (void) dealloc
{
  self.data = nil;
  self.responseHeaders = nil;
  self.resultFilename = nil;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

#pragma mark NSURLConnection Delegates

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
  NSLog(@"NSURLConnection delegate didReceiveResponse: %x", (int)response);
  
  // Record http status result
  
  if ([response respondsToSelector:@selector(statusCode)]) {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    int statusCode = (int) [httpResponse statusCode];
    self->httpStatusCode = statusCode;
    NSLog(@"httpStatusCode was %d", statusCode);

    // Dump HTTP headers
    
    NSDictionary *allHeaderFields = [httpResponse allHeaderFields];
    
    for (NSString *header in [allHeaderFields allKeys]) {
      NSLog(@"http header \"%@\" => \"%@\"", header, [allHeaderFields objectForKey:header]);
    }
    
    // Save headers
    
    self.responseHeaders = allHeaderFields;

    if (statusCode == 200) {
      // Query "Content-Length" when successful to find out how many bytes will be downloaded
      NSString *contentLengthStr = [allHeaderFields objectForKey:@"Content-Length"];
      NSInteger contentLengthInt = [contentLengthStr intValue];
      if (contentLengthInt > 0) {
        self->contentLength = (int) contentLengthInt;
      }
    }
  }  
}

// Append NSData to end of file.

- (BOOL) appendToFile:(NSString*)path
                 data:(NSData*)data
{
  NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
  
  if(fh)
  @try
  {
    [fh seekToEndOfFile];
    [fh writeData:data];
    [fh closeFile];
    return YES;
  }
  @catch(id error) {}
  
  return NO;
}

- (void) connection:(NSURLConnection*)connection didReceiveData:(NSData*)data
{
  //NSLog(@"NSURLConnection delegate didReceiveData: %x (%d bytes)", data, [data length]);
  
  if (self.data == nil) {
    // Data is incrementally written to a file as it is downloaded.
    
    NSAssert(self.resultFilename, @"resultFilename can't be nil");
    
    BOOL worked = [self appendToFile:self.resultFilename data:data];
    NSAssert(worked, @"worked");
  } else {
    [self.data appendData:data];    
  }
  
  downloadedBytes += [data length];
  
  // Deliver event to indicate download progress
  
  float progressPercent = 0.0f;
  
  if (self->contentLength > 0) {
    progressPercent = ((float)downloadedBytes) / self->contentLength;
  }
  NSNumber *progressPercentNum = [NSNumber numberWithFloat:progressPercent];
  
  NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                            data, @"PROGRESSDATA",
                            progressPercentNum, @"PROGRESSPERCENT",
                            nil];

  NSAssert([[userInfo allKeys] count] == 2, @"wrong key count");
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AsyncURLDownloaderConnectionDelegateProgress object:self userInfo:userInfo];
}

- (void) doneLoadingData:(NSURLConnection*)connection error:(NSError*)error
{
  NSLog(@"doneLoadingData: %x %x : %d bytes", (int)connection, (int)error, (int)[self.data length]);
  
  // Post notification that contains the HTTP status code, the data, and an error object if there was an error

  NSData *data;
  
  if (self.data == nil) {
    // Data was incrementally saved into a file, send an empty data argument in this case
    data = [NSData data];
  } else {
    // Create immutable copy of the data so it can be passed to notification targets in
    // another thread safely. Also deallocate the possibly large buffer.
    
    data = [NSData dataWithData:self.data];
    NSAssert(data != nil, @"data can't be nil");
    self.data = nil;
  }

  if (error != nil) {
    NSLog(@"NSURLConnection Error - \"%@\" %d %@",
          [error localizedDescription],
          (int)error.code,
          [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
    
    // HTTP 408 "Request Timeout"
    // The client did not produce a request within the time that the server was prepared to wait.
    // The client MAY repeat the request without modifications at any later time.
    
    // HTTP 500 "Internal Server Error"
    // Server can't respond to the request.

    // 502 "Bad Gateway"
    // The server, while acting as a gateway or proxy, received an invalid response from the upstream server it accessed
    // in attempting to fulfill the request.
    
    // HTTP 503 "Service Unavailable"
    // The server is currently unable to handle the request due to a temporary overloading or maintenance of the server.
    // The implication is that this is a temporary condition which will be alleviated after some delay.
    // If known, the length of the delay MAY be indicated in a Retry-After header. If no Retry-After is given,
    // the client SHOULD handle the response as it would for a 500 response.

    // HTTP 504 "Gateway Timeout"
    // The server, while acting as a gateway or proxy, did not receive a timely response from the upstream server
    // specified by the URI (e.g. HTTP, FTP, LDAP) or some other auxiliary server (e.g. DNS) it needed to access
    // in attempting to complete the request.
    
    BOOL handledError = FALSE;
    int httpStatus = -1;
    
    NSString *nsErrStr = @"NSURLErrorDomain";
    
    if ([error.domain isEqualToString:nsErrStr]) {
      // No internet connection error or timeout, did not invoke didReceiveResponse
      // so we need to explicitly set the http status code to indicate an error condition.
      // Check for known network error codes, translate network errors into HTTP 502.
      // CFNetwork.framework/Headers/CFNetworkErrors.h    
      
      if (error.code == kCFURLErrorTimedOut) {
        handledError = TRUE;
        httpStatus = 504; // "Gateway Timeout"
      } else if (
                 (error.code <= kCFURLErrorUnknown) ||
                 (error.code >= kCFURLErrorDataLengthExceedsMaximum)
                 ) {
        // CFURL and CFURLConnection Errors
        handledError = TRUE;
        httpStatus = 502; // "Bad Gateway"
      }
    }
    
    if (!handledError)
    {
      NSString *msg = [NSString stringWithFormat:@"unhandled NSURLConnection error \"%@\" %d : \"%@\"",
                       error.domain, (int)error.code, [error localizedDescription]];
      NSAssert(FALSE, msg);
    }
    
    self->httpStatusCode = httpStatus;
  }
  
  NSAssert(self->httpStatusCode != 0, @"can't report a http status code of 0");
  
  id headersObj = self.responseHeaders;
  if (headersObj == nil) {
    headersObj = [NSNull null];
  }
  
  // Can't pass nill as error, use NSNull instead
  id errorObj = error;
  if (errorObj == nil) {
    errorObj = [NSNull null];
  }
  
  NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithInt:self->httpStatusCode], @"HTTPSTATUS",
                            data, @"DATA",
                            errorObj, @"ERROR",
                            headersObj, @"RESPONSEHEADERS",
                            nil];
  NSAssert([[userInfo allKeys] count] == 4, @"wrong key count");
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AsyncURLDownloaderConnectionDelegateDidFinish object:self userInfo:userInfo];
}

- (void) connectionDidFinishLoading:(NSURLConnection*)connection
{
  NSLog(@"NSURLConnection delegate connectionDidFinishLoading");
  [self doneLoadingData:connection error:nil];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError*)error
{
  NSLog(@"NSURLConnection delegate didFailWithError");
  [self doneLoadingData:connection error:error];
}

// Auth methods needed for self-signed certs over https

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
  NSLog(@"NSURLConnection delegate canAuthenticateAgainstProtectionSpace");
  return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  NSLog(@"NSURLConnection delegate didReceiveAuthenticationChallenge");
  if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    // Allow any self-signed ssl cert
    if (TRUE) {
      //NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
      NSURLCredential *credential = [[NSURLCredential alloc] initWithTrust:challenge.protectionSpace.serverTrust];
      
#if __has_feature(objc_arc)
#else
      credential = [credential autorelease];
#endif // objc_arc

      [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
    }
  }
  [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

@end // Class AsyncURLDownloaderConnectionDelegate
