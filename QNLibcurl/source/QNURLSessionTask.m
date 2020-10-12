//
//  QNURLSessionTask.m
//  QNLibcurl
//
//  Created by yangsen on 2020/8/25.
//  Copyright © 2020 yangsen. All rights reserved.
//

#import "curl.h"
#import "QNURLSessionTask.h"
#import "QNURLSession.h"
#import "QNURLSessionConfiguration.h"


#define qn_curl_error(error_code,error_desc) ([[NSError alloc] initWithDomain:@"libcurlRequest" code:error_code userInfo:@{@"error" : error_desc ?: @"libcurl error"}])

#define qn_curl_easy_setopt(handle,opt,param,error,error_desc) \
{ \
    CURLcode code = curl_easy_setopt(handle,opt,param); \
    if (code != CURLE_OK) { \
        *error = qn_curl_error(code, error_desc); \
        return; \
    } \
}

@interface QNURLSessionTaskTransactionMetrics()
@property (nullable, copy) NSURLRequest *request;
@property (nullable, copy) NSURLResponse *response;

@property (nullable, copy) NSDate *fetchStartDate;
@property (nullable, copy) NSDate *domainLookupStartDate;
@property (nullable, copy) NSDate *domainLookupEndDate;

@property (nullable, copy) NSDate *connectStartDate;
@property (nullable, copy) NSDate *secureConnectionStartDate;
@property (nullable, copy) NSDate *secureConnectionEndDate;
@property (nullable, copy) NSDate *connectEndDate;

@property (nullable, copy) NSDate *requestStartDate;
@property (nullable, copy) NSDate *requestEndDate;

@property (nullable, copy) NSDate *responseStartDate;
@property (nullable, copy) NSDate *responseEndDate;

@property (nullable,    copy) NSString *networkProtocolName;
@property (nonatomic, assign) BOOL proxyConnection;

@property (nonatomic, assign) int64_t countOfRequestHeaderBytesSent;
@property (nonatomic, assign) int64_t countOfRequestBodyBytesSent;
@property (nonatomic, assign) int64_t countOfRequestBodyBytesBeforeEncoding;

@property (nonatomic, assign) int64_t countOfResponseHeaderBytesReceived;
@property (nonatomic, assign) int64_t countOfResponseBodyBytesReceived;
@property (nonatomic, assign) int64_t countOfResponseBodyBytesAfterDecoding;

@property (nullable,    copy) NSString *localAddress;
@property (nullable,    copy) NSNumber *localPort;

@property (nullable,    copy) NSString *remoteAddress;
@property (nullable,    copy) NSNumber *remotePort;
@end
@implementation QNURLSessionTaskTransactionMetrics
@end

@interface QNURLSessionTaskMetrics()
@property (  copy) NSArray<QNURLSessionTaskTransactionMetrics *> *transactionMetrics;
@property (  copy) NSDate *startDate;
@property (  copy) NSDate *endDate;
@property (assign) NSUInteger redirectCount;
@end
@implementation QNURLSessionTaskMetrics
@end

@interface QNURLSessionTask()

@property (nonatomic, strong) NSOperationQueue *delegateOperationQueue;
@property (nonatomic, strong) NSOperationQueue *taskOperationQueue;
@property (nonatomic,   weak) id <QNURLSessionDataTaskDelegate> delegate;

@property (nonatomic, strong) QNURLSession *urlSession;

@property (nonatomic, strong) QNURLSessionTaskTransactionMetrics *transactionMetrics;
@property (nonatomic, strong) QNURLSessionTaskMetrics *taskMetrics;
@property (nonatomic, strong) NSData *uploadData;
@property (nonatomic,   copy) NSURLRequest *originalRequest;
@property (nonatomic,   copy) NSURLRequest *currentRequest;
@property (nonatomic, strong) NSMutableDictionary *responseHeader;
@property (nonatomic,   copy) NSURLResponse *response;

@property (nonatomic, assign) BOOL isCancel;
@property (nonatomic, strong) NSProgress *progress;

@property (nonatomic, strong) NSDate *lastSendProgressCallBackDate;
@property (nonatomic, strong) NSDate *lastReceiveProgressCallBackDate;
@property (nonatomic, assign) int64_t countOfBytesReceived;
@property (nonatomic, assign) int64_t countOfBytesSent;
@property (nonatomic, assign) int64_t countOfBytesExpectedToSend;
@property (nonatomic, assign) int64_t countOfBytesExpectedToReceive;

@property (nonatomic, assign) NSURLSessionTaskState state;
@property (nonatomic,   copy) NSError *error;

- (BOOL)shouldContinue;
- (void)receiveHeaderField:(NSData *)data;
- (NSData *)readData:(unsigned long)size;
- (void)receiveData:(NSData *)data;
- (void)updateProgress:(double)downloadTotal
           downloadNow:(double)downloadNow
           uploadTotal:(double)uploadTotal
             uploadNow:(double)uploadNow;
@end

int CurlDebugCallback(CURL *curl, curl_infotype infoType, char *info, size_t infoLen, void *contextInfo) {
    
    NSData *infoData = [NSData dataWithBytes:info length:infoLen];
    NSString *infoStr = [[NSString alloc] initWithData:infoData encoding:NSUTF8StringEncoding];
    if (infoStr) {
        infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
        infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
        switch (infoType) {
            case CURLINFO_HEADER_IN:
                infoStr = [@"" stringByAppendingString:infoStr];
                break;
            case CURLINFO_HEADER_OUT:
                infoStr = [infoStr stringByReplacingOccurrencesOfString:@"\n" withString:@"\n>> "];
                infoStr = [NSString stringWithFormat:@">> %@\n", infoStr];
                break;
            case CURLINFO_DATA_IN:
                infoStr = @"data download";
                break;
            case CURLINFO_DATA_OUT:
                infoStr = @"data upload";
                break;
            case CURLINFO_SSL_DATA_IN:
                infoStr = [infoStr stringByAppendingString:@"\n"];
                break;
            case CURLINFO_SSL_DATA_OUT:
                infoStr = [infoStr stringByAppendingString:@"\n"];
                break;
            case CURLINFO_END:
                infoStr = [infoStr stringByAppendingString:@"\n"];
                break;
            case CURLINFO_TEXT:
                infoStr = [@"-- " stringByAppendingString:infoStr];
                break;
            default:
                break;
        }
        NSLog(@"Debug: %@", infoStr);
    }
    return 0;
}

size_t CurlReceiveHeaderCallback(char *buffer, size_t size, size_t nitems, void *userData){
    const size_t sizeInBytes = size * nitems;
    QNURLSessionTask *task = (__bridge QNURLSessionTask *)userData;
    NSData *data = [[NSData alloc] initWithBytes:buffer length:sizeInBytes];
    [task receiveHeaderField:data];
    return nitems * size;
}

size_t CurlReadCallback(void *ptr, size_t size, size_t nmemb, void *userData) {
    const size_t sizeInBytes = size * nmemb;
    QNURLSessionTask *task = (__bridge QNURLSessionTask *)userData;
    NSData *data = [task readData:sizeInBytes];
    if (data) {
        memcpy(ptr, [data bytes], data.length);
        return [data length];
    } else {
        return 0U;
    }
}

size_t CurlWriteCallback(char *ptr, size_t size, size_t nmemb, void *userData) {
    const size_t sizeInBytes = size * nmemb;
    QNURLSessionTask *task = (__bridge QNURLSessionTask *)userData;
    NSData *data = [[NSData alloc] initWithBytes:ptr length:sizeInBytes];
    [task receiveData:data];
    return sizeInBytes;
}

int CurlProgressCallback(void *client, double downloadTotal, double downloadNow, double uploadTotal, double uploadNow) {
    QNURLSessionTask *task = (__bridge QNURLSessionTask *)client;
    if ([task shouldContinue]) {
        [task updateProgress:downloadTotal downloadNow:downloadNow uploadTotal:uploadTotal uploadNow:uploadNow];
        return 0;
    } else {
        return NSURLErrorCancelled;
    }
}

@implementation QNURLSessionTask

+ (void)initResource{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        curl_global_init(CURL_GLOBAL_ALL);
    });
}
+ (void)releaseResource{
    
}

- (instancetype)initWithURLSession:(QNURLSession *)urlSession
                           request:(NSURLRequest *)request
                          delegate:(id<QNURLSessionDataTaskDelegate>)delegate
            delegateOperationQueue:(NSOperationQueue *)delegateOperationQueue{
    if (self = [super init]) {
        self.originalRequest = request;
        self.delegate = delegate;
        self.delegateOperationQueue = delegateOperationQueue;
        self.urlSession = urlSession;
        [self initData];
    }
    return self;
}

- (void)initData{
    
    self.isCancel = NO;

    self.taskOperationQueue = [[NSOperationQueue alloc] init];
    self.taskOperationQueue.maxConcurrentOperationCount = 1;
    if (self.delegateOperationQueue == nil) {
        self.delegateOperationQueue = [[NSOperationQueue alloc] init];
    }
    
    self.responseHeader = [NSMutableDictionary dictionary];
    self.transactionMetrics = [[QNURLSessionTaskTransactionMetrics alloc] init];
    self.transactionMetrics.request = self.originalRequest;
    self.taskMetrics = [[QNURLSessionTaskMetrics alloc] init];
    self.uploadData = [self getRequestData:self.originalRequest];
}


- (void)initCurlRequestDefaultOptions:(CURL *)curl error:(NSError **)error{

    qn_curl_easy_setopt(curl, CURLOPT_DEBUGFUNCTION, CurlDebugCallback, error, @"debug function set 0 error");
    qn_curl_easy_setopt(curl, CURLOPT_DEBUGDATA, self, error, @"debug function set 1 error");
    
    qn_curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, CurlReceiveHeaderCallback, error, @"header function set 0 error");
    qn_curl_easy_setopt(curl, CURLOPT_HEADERDATA, self, error, @"header function set 1 error");
    
//    qn_curl_easy_setopt(curl, CURLOPT_READFUNCTION, CurlReadCallback, error, @"read function set 0 error");
//    qn_curl_easy_setopt(curl, CURLOPT_READDATA, self, error, @"read function set 1 error");
    
    qn_curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, CurlWriteCallback, error, @"write function set 0 error");
    qn_curl_easy_setopt(curl, CURLOPT_WRITEDATA, self, error, @"write function set 1 error");
    
    qn_curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L, error, @"progress function set 0 error");
    qn_curl_easy_setopt(curl, CURLOPT_PROGRESSFUNCTION, CurlProgressCallback, error, @"progress function set 1 error");
    qn_curl_easy_setopt(curl, CURLOPT_PROGRESSDATA, self, error, @"progress function set 2 error");
    
    // CA root certs - loaded into project from libcurl http://curl.haxx.se/ca/cacert.pem
    NSBundle *classBundle = [NSBundle bundleForClass:[QNURLSessionTask class]];
    NSBundle *bundle = [NSBundle bundleWithPath:[classBundle pathForResource:@"QNLibcurl" ofType:@"bundle"]];
    if (bundle == nil) {
        bundle = [NSBundle bundleWithPath:[classBundle pathForResource:@"QNLibcurl-macOS/QNLibcurl" ofType:@"bundle"]];
    }
    NSString *cacertPath = [bundle pathForResource:@"cacert" ofType:@"pem"];
    qn_curl_easy_setopt(curl, CURLOPT_CAINFO, [cacertPath UTF8String], error, @"ca info set error"); // set root CA certs

    
    // Set some CURL options
    curl_easy_setopt(curl, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
    curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
    
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_SERVER_RESPONSE_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_ACCEPTTIMEOUT_MS, 5000L);
    curl_easy_setopt(curl, CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS, 300L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    
    curl_easy_setopt(curl, CURLOPT_TCP_KEEPALIVE, 1L);
    curl_easy_setopt(curl, CURLOPT_TCP_KEEPIDLE, 10L);
    curl_easy_setopt(curl, CURLOPT_TCP_KEEPINTVL, 10L);
    curl_easy_setopt(curl, CURLOPT_TCP_FASTOPEN, 1L);
    
//    curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);
    
//    curl_easy_setopt(curl, CURLOPT_MAXCONNECTS, 0L);
//    curl_easy_setopt(curl, CURLOPT_FORBID_REUSE, 1L);
    curl_easy_setopt(curl, CURLOPT_DNS_CACHE_TIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_3 /*| CURL_HTTP_VERSION_2_0 | CURL_HTTP_VERSION_1_1 | CURL_HTTP_VERSION_1_0*/);
    curl_easy_setopt(curl, CURLOPT_SSLVERSION, CURL_SSLVERSION_DEFAULT);
//    curl_easy_setopt(curl, CURLOPT_SSL_CIPHER_LIST, [@"ALL" UTF8String]);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 1L);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST,nil);
    
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
}

- (void)initCurlRequestCustomOptions:(CURL *)curl{
    
    //custom option
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, self.originalRequest.timeoutInterval);
    if (self.urlSession.configuration.HTTPShouldUsePipelining) {
        curl_easy_setopt(curl, CURLOPT_PIPEWAIT, 1);
    }
}

- (void)initCurlDnsResolver:(CURL *)curl dnsResolver:(struct curl_slist *)dnsResolver{
    // dnsResolve
    NSArray *dnsResolverArray = [self.urlSession.configuration.dnsResolverArray copy];
    if (dnsResolverArray.count > 0) {
        for (QNDnsResolver *resolver in dnsResolverArray) {
            NSString *resolverString = [resolver resolverString];
            if (resolverString.length > 0) {
                dnsResolver = curl_slist_append(NULL, [resolverString UTF8String]);
            }
        }
    }
    
    if (dnsResolver != NULL) {
        curl_easy_setopt(curl, CURLOPT_RESOLVE, dnsResolver);
    }
}

- (void)initCurlRequestHeader:(CURL *)curl headerList:(struct curl_slist *)headerList error:(NSError **)error {
    //header
    NSMutableDictionary *headerInfo = [self.originalRequest.allHTTPHeaderFields mutableCopy];
    [headerInfo addEntriesFromDictionary:self.urlSession.configuration.HTTPAdditionalHeaders];
    for(NSString *key in headerInfo.allKeys){
        NSObject *value = [self.originalRequest.allHTTPHeaderFields valueForKey:key];
        NSString *headerField = [NSString stringWithFormat:@"%@: %@", key, value];
        headerList = curl_slist_append(headerList, [headerField UTF8String]);
    }
    qn_curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headerList, error, @"header set error");
}
   
- (void)initCurlRequestBody:(CURL *)curl error:(NSError **)error{
    //body
//    qn_curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)self.uploadData.length, error, @"body set error");
    qn_curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (curl_off_t)self.uploadData.length, error, @"body set error");
    qn_curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [self.uploadData bytes], error, @"body set error");
}

- (void)initCurlRequestMethod:(CURL *)curl error:(NSError **)error{
    
    //method
    NSString *httpMethod = self.originalRequest.HTTPMethod;
    if ([httpMethod isEqualToString:@"GET"]) {
        qn_curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L, error, @"Get method set error");
    } else if ([httpMethod isEqualToString:@"POST"]) {
        qn_curl_easy_setopt(curl, CURLOPT_POST, 1L, error, @"POST method set error");
    } else if ([httpMethod isEqualToString:@"PUT"]) {
        qn_curl_easy_setopt(curl, CURLOPT_PUT, 1L, error, @"PUT method set error");
    } else {
        *error = qn_curl_error(2, @"method set error");
    }
}
- (void)initCurlRequestProxy:(CURL *)curl{
    curl_easy_setopt(curl, CURLOPT_URL, _originalRequest.URL.absoluteString.UTF8String);
    
    NSString *proxyHost = self.urlSession.configuration.connectionProxyDictionary[(NSString *)kCFStreamPropertyHTTPProxyHost];
    NSString *proxyPort = self.urlSession.configuration.connectionProxyDictionary[(NSString *)kCFStreamPropertyHTTPProxyPort];
    if (proxyHost && proxyPort) {
        NSString *proxy = [NSString stringWithFormat:@"%@:%@", proxyHost, proxyPort];
        CURLcode code = curl_easy_setopt(curl, CURLOPT_PROXY, [proxy UTF8String]);
        self.transactionMetrics.proxyConnection = code == CURLE_OK;
    }
}

- (void)performRequest:(CURL *)curl error:(NSError **)error{
    
    char errBuffer[CURL_ERROR_SIZE];
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errBuffer);
    
    CURLcode code = curl_easy_perform(curl);
    if (code != CURLE_OK) {
        NSString *errorInfo = [[NSString alloc] initWithUTF8String:errBuffer];
        *error = qn_curl_error(code, errorInfo ?: @"curl request perform error");
    }
}

- (void)prepare{
    
}

- (void)cancel{
    self.isCancel = true;
}

- (void)resume{
    __weak typeof(self) weakSelf = self;
    [self addTask:^{

        __strong typeof(self)strongSelf = weakSelf;
        
        NSError *error = nil;
        struct curl_slist *dnsResolver = NULL;
        struct curl_slist *headerList = NULL;
        CURL *curl = curl_easy_init();
        
        [strongSelf initCurlRequestDefaultOptions:curl error:&error];
        if (error) {
            goto curl_perform_complete;
        }
        [strongSelf initCurlRequestCustomOptions:curl];
        [strongSelf initCurlDnsResolver:curl dnsResolver:dnsResolver];
        [strongSelf initCurlRequestHeader:curl headerList:headerList error:&error];
        if (error) {
            goto curl_perform_complete;
        }
        [strongSelf initCurlRequestBody:curl error:&error];
        [strongSelf initCurlRequestMethod:curl error:&error];
        if (error) {
            goto curl_perform_complete;
        }
        if (error) {
            goto curl_perform_complete;
        }
        [strongSelf initCurlRequestProxy:curl];
        
        [strongSelf performRequest:curl error:&error];
        if (error) {
            goto curl_perform_complete;
        }
        
    curl_perform_complete:
        strongSelf.response = [strongSelf getResponse:curl];
        [strongSelf didReceiveResponse:strongSelf.response];
        [strongSelf setRequestTaskTransactionMetrics:curl];
        strongSelf.transactionMetrics.response = strongSelf.response;
        
        [strongSelf didFinishCollectingMetrics];
        [strongSelf didCompleteWithError:error];
        
        if (dnsResolver != NULL) {
            curl_slist_free_all(dnsResolver);
        }
        if (headerList != NULL) {
            curl_slist_free_all(headerList);
        }
        if (curl != NULL) {
            curl_easy_cleanup(curl);
        }
    }];
}

//MARK: -- private logic
- (void)setRequestTaskTransactionMetrics:(CURL *)curl{
    if (curl == NULL) {
        return;
    }
    
    long localPort;
    long remotePort;
    char *localIP = NULL;
    char *remoteIP = NULL;
    curl_easy_getinfo(curl, CURLINFO_LOCAL_PORT, &localPort);
    curl_easy_getinfo(curl, CURLINFO_LOCAL_IP, &localIP);
    curl_easy_getinfo(curl, CURLINFO_PRIMARY_PORT, &remotePort);
    curl_easy_getinfo(curl, CURLINFO_PRIMARY_IP, &remoteIP);
    
    NSString *localIPString = nil;
    NSString *remoteIPString = nil;
    if (localIP != NULL) {
        localIPString = [NSString stringWithUTF8String:localIP];
    }
    if (remoteIP != NULL) {
        remoteIPString = [NSString stringWithUTF8String:remoteIP];
    }
    
    self.transactionMetrics.localPort = localPort > 0 ? @(localPort) : nil;
    self.transactionMetrics.localAddress = localIPString;
    self.transactionMetrics.remotePort = remotePort > 0 ? @(remotePort) : nil;
    self.transactionMetrics.remoteAddress = remoteIPString;
    
    curl_off_t total_time, name_lookup_time, connect_time, app_connect_time,
    pre_transfer_time, start_transfer_time, redirect_time, redirect_count;
    curl_easy_getinfo(curl, CURLINFO_TOTAL_TIME_T, &total_time);
    curl_easy_getinfo(curl, CURLINFO_NAMELOOKUP_TIME_T, &name_lookup_time);
    curl_easy_getinfo(curl, CURLINFO_CONNECT_TIME_T, &connect_time);
    curl_easy_getinfo(curl, CURLINFO_APPCONNECT_TIME_T, &app_connect_time);
    curl_easy_getinfo(curl, CURLINFO_PRETRANSFER_TIME_T, &pre_transfer_time);
    curl_easy_getinfo(curl, CURLINFO_STARTTRANSFER_TIME_T, &start_transfer_time);
    curl_easy_getinfo(curl, CURLINFO_REDIRECT_TIME_T, &redirect_time);
    curl_easy_getinfo(curl, CURLINFO_REDIRECT_COUNT, &redirect_count);
    
    double scale = 0.0000001;
    NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:total_time * scale];
    self.transactionMetrics.fetchStartDate = startDate;
    
    self.transactionMetrics.domainLookupStartDate = startDate;
    self.transactionMetrics.domainLookupEndDate = [startDate dateByAddingTimeInterval:name_lookup_time * scale];
    
    self.transactionMetrics.connectStartDate = self.transactionMetrics.domainLookupEndDate;
    self.transactionMetrics.secureConnectionStartDate = self.transactionMetrics.domainLookupEndDate;
    self.transactionMetrics.secureConnectionEndDate = [startDate dateByAddingTimeInterval:connect_time * scale];
    self.transactionMetrics.connectEndDate = [startDate dateByAddingTimeInterval:app_connect_time * scale];
    
    self.transactionMetrics.requestStartDate = self.transactionMetrics.connectEndDate;
    self.transactionMetrics.requestEndDate = [startDate dateByAddingTimeInterval:start_transfer_time * scale];
    
    self.transactionMetrics.responseStartDate = self.transactionMetrics.requestEndDate;
    self.transactionMetrics.responseEndDate = [startDate dateByAddingTimeInterval:total_time * scale];
    
    
    curl_off_t request_header_size, request_body_size, response_header_size, response_body_size;
    if ([self.originalRequest.allHTTPHeaderFields isKindOfClass:[NSDictionary class]]) {
        request_header_size = [NSJSONSerialization dataWithJSONObject:self.originalRequest.allHTTPHeaderFields options:NSJSONWritingFragmentsAllowed error:nil].length;
    } else {
        request_header_size = 0;
    }
    
    curl_easy_getinfo(curl, CURLINFO_SIZE_UPLOAD_T, &request_body_size);
    curl_easy_getinfo(curl, CURLINFO_SIZE_DOWNLOAD_T, &response_body_size);
    curl_easy_getinfo(curl, CURLINFO_HEADER_SIZE, &response_header_size);

    curl_easy_getinfo(curl, CURLINFO_CONTENT_LENGTH_UPLOAD_T, &request_body_size);
    curl_easy_getinfo(curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &response_body_size);
    
    self.transactionMetrics.countOfRequestHeaderBytesSent = request_header_size;
    self.transactionMetrics.countOfRequestBodyBytesSent = request_body_size;
    self.transactionMetrics.countOfResponseHeaderBytesReceived = response_header_size;
    self.transactionMetrics.countOfResponseBodyBytesReceived = response_body_size;
    
    curl_off_t protocol;
    curl_easy_getinfo(curl, CURLINFO_PROTOCOL, &protocol);
    if (protocol == CURLPROTO_HTTP) {
        self.transactionMetrics.networkProtocolName = @"HTTP";
    } else if (protocol == CURLPROTO_HTTPS) {
        self.transactionMetrics.networkProtocolName = @"HTTPS";
    }
    
    self.taskMetrics.redirectCount = (long)redirect_count;
    self.taskMetrics.startDate = self.transactionMetrics.fetchStartDate;
    self.taskMetrics.endDate = self.transactionMetrics.responseEndDate;
    self.taskMetrics.transactionMetrics = @[self.transactionMetrics];
}

- (NSURLResponse *)getResponse:(CURL *)curl{
    if (curl == NULL) {
        return nil;
    }
    long statusCode, http_ver;
    char *redirect_url2 = NULL;
    
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);
    curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &redirect_url2);
    curl_easy_getinfo(curl, CURLINFO_HTTP_VERSION, &http_ver);
    
    if (self.isCancel) {
        statusCode = NSURLErrorCancelled;
    }
    
    NSString *HTTPVersion = @"";
    if(http_ver == CURL_HTTP_VERSION_1_0) {
        HTTPVersion = @"HTTP/1.0";
    } else if(http_ver == CURL_HTTP_VERSION_1_1) {
        HTTPVersion = @"HTTP/1.1";
    } else if(http_ver == CURL_HTTP_VERSION_2_0 ||
              http_ver == CURL_HTTP_VERSION_2TLS ||
              http_ver == CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE) {
        HTTPVersion = @"HTTP/2";
    } else if(http_ver == CURL_HTTP_VERSION_3) {
        HTTPVersion = @"HTTP/3";
    }
    return [[NSHTTPURLResponse alloc] initWithURL:self.originalRequest.URL
                                       statusCode:statusCode
                                      HTTPVersion:HTTPVersion
                                     headerFields:[self.responseHeader copy]];
}

- (BOOL)shouldContinue{
    return !self.isCancel;
}

- (NSData *)readData:(unsigned long)size{
    if (self.originalRequest.HTTPBody) {
        NSData *body = self.uploadData;
        NSData *data = nil;
        unsigned long lastSize = (unsigned long)(body.length - self.countOfBytesSent);
        size = MIN(lastSize, size);
        if (size <= 0) {
            return nil;
        } else {
            data = [body subdataWithRange:NSMakeRange((unsigned int)self.countOfBytesSent, size)];
            self.countOfBytesSent += data.length;
            return data;
        }
    } else {
        return nil;
    }
}

- (void)receiveHeaderField:(NSData *)data{
    NSString *fieldString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([fieldString rangeOfString:@":"].location == NSNotFound) {
        return;
    }
    fieldString = [fieldString stringByReplacingOccurrencesOfString:@" " withString:@""];
    fieldString = [fieldString stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    fieldString = [fieldString stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    NSArray *fieldArray = [fieldString componentsSeparatedByString:@":"];
    NSLog(@"== header: %@", fieldString);
    
    NSString *key = nil;
    NSString *value = nil;
    if (fieldArray.count < 2) {
        return;
    } else if (fieldArray.count == 2) {
        key = fieldArray[0];
        value = fieldArray[1];
    } else {
        key = fieldArray[0];
        value = [[fieldArray subarrayWithRange:NSMakeRange(1, fieldArray.count-1)] componentsJoinedByString:@":"];
    }
    
    [self.responseHeader setObject:value forKey:key];
}

- (NSData *)getRequestData:(NSURLRequest *)request{
    if (request.HTTPBody || ![request.HTTPMethod isEqualToString:@"POST"]) {
        return request.HTTPBody;
    }
    
    NSInteger maxLength = 1024;
    uint8_t d[maxLength];
    
    NSInputStream *stream = request.HTTPBodyStream;
    NSMutableData *data = [NSMutableData data];
    
    [stream open];
    
    BOOL end = NO;
    
    while (!end) {
        NSInteger bytesRead = [stream read:d maxLength:maxLength];
        if (bytesRead == 0) {
            end = YES;
        } else if (bytesRead == -1){
            end = YES;
        } else if (stream.streamError == nil){
            [data appendBytes:(void *)d length:bytesRead];
       }
    }
    [stream close];
    return [data copy];
}

- (void)receiveData:(NSData *)data{
    if (self.delegate == nil || ![self.delegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self addDelegateQueueTask:^{
        __strong typeof(self)strongSelf = weakSelf;
        [strongSelf.delegate URLSession:strongSelf.urlSession dataTask:strongSelf didReceiveData:data];
    }];
}

- (void)updateProgress:(double)downloadTotal
           downloadNow:(double)downloadNow
           uploadTotal:(double)uploadTotal
             uploadNow:(double)uploadNow{
    
    if (self.delegate == nil) {
        return;
    }
    
    self.countOfBytesExpectedToSend = (int64_t)uploadTotal;
    int64_t sendBodyLength = (int64_t)uploadNow - self.countOfBytesSent;
    self.countOfBytesSent = (int64_t)uploadNow;
    
    self.countOfBytesExpectedToReceive = (int64_t)downloadTotal;
    int64_t receiveBodyLength = (int64_t)downloadNow - self.countOfBytesReceived;
    self.countOfBytesReceived = (int64_t)downloadNow;
    
    NSDate *currentDate = [NSDate date];
    if (uploadNow > 0 && sendBodyLength > 0 &&
        [self.delegate respondsToSelector:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)] &&
        (!self.lastSendProgressCallBackDate || [currentDate timeIntervalSinceDate:self.lastSendProgressCallBackDate] > 0.5)) {
        self.lastSendProgressCallBackDate = currentDate;
        __weak typeof(self) weakSelf = self;
        [self addDelegateQueueTask:^{
            __strong typeof(self)strongSelf = weakSelf;
            [strongSelf.delegate URLSession:strongSelf.urlSession task:strongSelf didSendBodyData:sendBodyLength totalBytesSent:(int64_t)uploadNow totalBytesExpectedToSend:(int64_t)uploadTotal];
        }];
    }
    
    if (downloadNow > 0 && receiveBodyLength > 0 &&
        [self.delegate respondsToSelector:@selector(URLSession:task:didReceiveBodyData:totalBytesReceive:totalBytesExpectedToReceive:)] &&
        (!self.lastReceiveProgressCallBackDate || [currentDate timeIntervalSinceDate:self.lastReceiveProgressCallBackDate] > 0.5)) {
        self.lastReceiveProgressCallBackDate = currentDate;
        __weak typeof(self) weakSelf = self;
        [self addDelegateQueueTask:^{
            __strong typeof(self)strongSelf = weakSelf;
            [strongSelf.delegate URLSession:strongSelf.urlSession task:strongSelf didReceiveBodyData:receiveBodyLength totalBytesReceive:(int64_t)downloadNow totalBytesExpectedToReceive:(int64_t)downloadTotal];
        }];
    }
}

- (void)didReceiveResponse:(NSURLResponse *)response{
    if (!self.delegate || ![self.delegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
        return;
    }
    void (^completionHandler)(NSURLSessionResponseDisposition disposition) = ^(NSURLSessionResponseDisposition disposition){
    };
    __weak typeof(self) weakSelf = self;
    [self addDelegateQueueTask:^{
    __strong typeof(self)strongSelf = weakSelf;
        [strongSelf.delegate URLSession:strongSelf.urlSession dataTask:strongSelf didReceiveResponse:response completionHandler:completionHandler];
    }];
}

- (void)didFinishCollectingMetrics{
    if (!self.delegate || ![self.delegate respondsToSelector:@selector(URLSession:task:didFinishCollectingMetrics:)]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self addDelegateQueueTask:^{
    __strong typeof(self)strongSelf = weakSelf;
        [strongSelf.delegate URLSession:strongSelf.urlSession task:strongSelf didFinishCollectingMetrics:strongSelf.taskMetrics];
    }];
}

- (void)didCompleteWithError:(NSError *)error{
    if (!self.delegate || ![self.delegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self addDelegateQueueTask:^{
    __strong typeof(self)strongSelf = weakSelf;
        [strongSelf.delegate URLSession:strongSelf.urlSession task:strongSelf didCompleteWithError:error];
    }];
}

- (void)addTask:(dispatch_block_t)task{
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:task];
    [self.taskOperationQueue addOperation:operation];
}

- (void)addDelegateQueueTask:(dispatch_block_t)task{
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:task];
    [self.delegateOperationQueue addOperation:operation];
}

@end


@implementation QNURLSessionDataTask

@end
