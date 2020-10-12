//
//  QNURLSession.m
//  QNLibcurl
//
//  Created by yangsen on 2020/8/24.
//  Copyright © 2020 yangsen. All rights reserved.
//

#import "QNURLSession.h"
#import "QNURLSessionTask.h"
#import "QNURLSessionConfiguration.h"

@interface QNURLSession()

@property (nonatomic, strong) NSOperationQueue *taskQueue;
@property (nonatomic, strong) NSOperationQueue *delegateQueue;
@property (nonatomic,   weak) id <QNURLSessionDataTaskDelegate> delegate;
@property (nonatomic, strong) QNURLSessionConfiguration *configuration;

@end
@implementation QNURLSession

+ (QNURLSession *)sharedSession{
    static QNURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        session = [[QNURLSession alloc] init];
    });
    return session;
}

- (instancetype)init{
    if (self = [super init]) {
        [QNURLSessionTask initResource];
        self.taskQueue = [[NSOperationQueue alloc]init];
        self.taskQueue.maxConcurrentOperationCount = 6;
        self.delegateQueue = [[NSOperationQueue alloc]init];
        self.taskQueue.maxConcurrentOperationCount = 3;
    }
    return self;
}
+ (QNURLSession *)sessionWithConfiguration:(QNURLSessionConfiguration *)configuration{
    return [self sessionWithConfiguration:configuration
                                 delegate:nil
                            delegateQueue:nil];
}

+ (QNURLSession *)sessionWithConfiguration:(QNURLSessionConfiguration *)configuration delegate:(nullable id <QNURLSessionDataTaskDelegate>)delegate delegateQueue:(nullable NSOperationQueue *)queue{
    QNURLSession *session = [[QNURLSession alloc] init];
    session.configuration = configuration;
    session.delegate = delegate;
    if (queue) {
        session.delegateQueue = queue;
    }
    return session;
}
@end

@implementation QNURLSession(QNURLSessionAsynchronousConvenience)

- (QNURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request{
    QNURLSessionDataTask *task = [[QNURLSessionDataTask alloc] initWithURLSession:self
                                                                          request:request
                                                                         delegate:self.delegate
                                                           delegateOperationQueue:self.delegateQueue];
    return task;
}

- (QNURLSessionDataTask *)dataTaskWithURL:(NSURL *)url{
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return [self dataTaskWithRequest:request];
}

@end

