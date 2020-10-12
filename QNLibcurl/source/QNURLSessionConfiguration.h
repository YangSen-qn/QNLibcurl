//
//  QNURLSessionConfiguration.h
//  QNLibcurl
//
//  Created by yangsen on 2020/8/24.
//  Copyright © 2020 yangsen. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface QNDnsResolver : NSObject

@property(nonatomic,   copy, readonly)NSString *host;
@property(nonatomic,   copy, readonly)NSString *ip;
@property(nonatomic, assign, readonly)NSInteger port;

- (instancetype)initWithHost:(NSString *)host
                          ip:(NSString *)ip
                        port:(NSInteger)port;

- (NSString *)resolverString;

@end

@interface QNURLSessionConfiguration : NSObject

@property (nonatomic, strong)NSArray <QNDnsResolver *> *dnsResolverArray;

/* The proxy dictionary, as described by <CFNetwork/CFHTTPStream.h> */
@property (nullable,    copy) NSDictionary *connectionProxyDictionary;

/* Allow the use of HTTP pipelining */
@property BOOL HTTPShouldUsePipelining;

/* Specifies additional headers which will be set on outgoing requests.
   Note that these headers are added to the request only if not already present. */
@property (nullable,    copy) NSDictionary *HTTPAdditionalHeaders;

@end

NS_ASSUME_NONNULL_END
