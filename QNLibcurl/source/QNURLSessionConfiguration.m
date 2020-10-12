//
//  QNURLSessionConfiguration.m
//  QNLibcurl
//
//  Created by yangsen on 2020/8/24.
//  Copyright © 2020 yangsen. All rights reserved.
//

#import "QNURLSessionConfiguration.h"

@implementation QNDnsResolver

- (instancetype)initWithHost:(NSString *)host
                          ip:(NSString *)ip
                        port:(NSInteger)port{
    if (self = [super init]) {
        _host = host;
        _ip = ip;
        _port = port;
    }
    return self;
}

- (NSString *)resolverString{
    return [NSString stringWithFormat:@"%@:%ld:%@", self.host, (long)self.port, self.ip];
}

@end
@implementation QNURLSessionConfiguration

@end
