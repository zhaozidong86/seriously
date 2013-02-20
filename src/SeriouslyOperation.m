//
//  SeriouslyOperation.m
//  Prototype
//
//  Created by Corey Johnson on 6/18/10.
//  Copyright 2010 Probably Interactive. All rights reserved.
//

#import "SeriouslyOperation.h"

#define KVO_SET(_key_, _value_) [self willChangeValueForKey:@#_key_]; \
self._key_ = (_value_); \
[self didChangeValueForKey:@#_key_]; 


@interface SeriouslyOperation (Private)

- (id)initWithRequest:(NSURLRequest *)urlRequest handler:(SeriouslyHandler)handler progressHandler:(SeriouslyProgressHandler)progressHandler;

@end


@implementation SeriouslyOperation

@synthesize isFinished = _isFinished;
@synthesize isExecuting = _isExecuting;
@synthesize isCancelled = _isCancelled;

- (void)dealloc {
    [_connection release];
    [_handler release];
    [_progressHandler release];
    [_response release];
    [_data release];
    [_error release];
	[_urlRequest release];
    
    [super dealloc];
}

+ (id)operationWithRequest:(NSURLRequest *)urlRequest handler:(SeriouslyHandler)handler progressHandler:(SeriouslyProgressHandler)progressHandler {
    // Don't you dare release this until everything is finished or canceled
    return [[self alloc] initWithRequest:urlRequest handler:handler progressHandler:progressHandler];
}

- (id)initWithRequest:(NSURLRequest *)urlRequest handler:(SeriouslyHandler)handler progressHandler:(SeriouslyProgressHandler)progressHandler {
    self = [super init];
    //_connection = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:NO];
    _handler = [handler copy];
    _progressHandler = [progressHandler copy];
    _data = [[NSMutableData alloc] init];
    
    _isFinished = NO;
    _isCancelled = NO;
    _isExecuting = NO;
    
    _urlRequest = [urlRequest retain];
    
    return self;
}

- (void)start {
    if (self.isCancelled || self.isFinished) return;

    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }

    KVO_SET(isExecuting, YES);
	
    _connection = [[NSURLConnection alloc] initWithRequest:_urlRequest delegate:self];
    [_connection start];

}

- (void)cancel {
    @synchronized(self) {
        if (self.isCancelled) return; // Already canceled

        KVO_SET(isCancelled, YES);
        KVO_SET(isFinished, YES);
        KVO_SET(isExecuting, NO);

        [_connection cancel];	
        [super cancel];
    }
    
    [self autorelease];
}

- (void)sendHandler:(NSURLConnection *)connection {
    if (self.isCancelled) [NSException raise:@"Seriously error" format:@"OH NO, THE URL CONNECTION WAS CANCELED BUT NOT CAUGHT"];

    KVO_SET(isExecuting, NO)
	KVO_SET(isFinished, YES)
    
    _handler(_data, _response, _error);

    [self autorelease];
}

// NSURLConnection Delegate
// ------------------------
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if (response != _response) {
        [_response release];
        _response = (NSHTTPURLResponse *) [response retain];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_data appendData:data];
    
    if (_progressHandler) {
        float percentComplete = _data.length / [[[_response allHeaderFields] objectForKey:@"Content-Length"] floatValue];
        _progressHandler(percentComplete, _data);
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (!self.isCancelled) {
        _error = [error retain];
        [_data release];
        _data = nil;
        [self sendHandler:connection];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {    
    if (!self.isCancelled) [self sendHandler:connection];
}

@end