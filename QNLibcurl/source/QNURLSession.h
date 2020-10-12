//
//  QNURLSession.h
//  QNLibcurl
//
//  Created by yangsen on 2020/8/24.
//  Copyright © 2020 yangsen. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol QNURLSessionDataTaskDelegate;
@class QNURLSessionConfiguration;
@class QNURLSessionDataTask;

NS_ASSUME_NONNULL_BEGIN

@interface QNURLSession : NSObject

@property (class, readonly, strong) QNURLSession *sharedSession;

+ (QNURLSession *)sessionWithConfiguration:(QNURLSessionConfiguration *)configuration;
+ (QNURLSession *)sessionWithConfiguration:(QNURLSessionConfiguration *)configuration delegate:(nullable id <QNURLSessionDataTaskDelegate>)delegate delegateQueue:(nullable NSOperationQueue *)queue;

@property (nullable, readonly, strong) NSOperationQueue *delegateQueue;
@property (nullable, readonly, weak) id <QNURLSessionDataTaskDelegate> delegate;
@property (nullable, readonly, strong) QNURLSessionConfiguration *configuration;

@end

@interface QNURLSession (QNURLSessionAsynchronousConvenience)

- (QNURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request;
- (QNURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;

//- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
//- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(nullable NSData *)bodyData completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
