//
//  ZYQRouter.m
//  ZYQRouter
//
//  Created by Zhao Yiqi on 2016/11/25.
//  Copyright © 2016年 Zhao Yiqi. All rights reserved.
//

#import "ZYQRouter.h"

#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const ZYQ_ROUTER_WILDCARD_CHARACTER = @"~";

NSString *const ZYQRouterParameterURL = @"ZYQRouterParameterURL";
NSString *const ZYQRouterParameterCompletion = @"ZYQRouterParameterCompletion";
NSString *const ZYQRouterParameterUserInfo = @"ZYQRouterParameterUserInfo";

@interface ZYQRouter ()
/**
 *  保存了所有已注册的 URL
 *  结构类似 @{@"beauty": @{@":id": {@"_", [block copy]}}}
 */
@property (nonatomic) NSMutableDictionary *routes;
@property (nonatomic) NSMutableDictionary *redirectRoutes;
@property (nonatomic) NSDictionary *unFoundRoutesBlock;


@property (nonatomic) NSMutableDictionary *targetsCache;
@property (nonatomic) NSMutableDictionary *notFoundBlocks;

@end

@implementation ZYQRouter

+ (instancetype)sharedIsntance
{
    static ZYQRouter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}


#pragma mark - URL Router -

+ (void)redirectURLPattern:(NSString *)URLPattern toURLPattern:(NSString*)newURLPattern{
    [[self sharedIsntance] addRedirectURLPattern:URLPattern toURLPattern:newURLPattern];
}

+ (void)registerURLPattern:(NSString *)URLPattern toHandler:(ZYQRouterHandler)handler
{
    [[self sharedIsntance] addURLPattern:URLPattern andHandler:handler];
}

+ (void)registerUnFoundURLPatternToObjectHandler:(ZYQRouterObjectHandler)handler{
    [[self sharedIsntance] setUnFoundRoutesBlock:@{@"block":[handler copy],@"type":@"ZYQRouterObjectHandler"}];
}

+ (void)registerUnFoundURLPatternToHandler:(ZYQRouterHandler)handler
{
    [[self sharedIsntance] setUnFoundRoutesBlock:@{@"block":[handler copy],@"type":@"ZYQRouterHandler"}];
}

+ (void)deregisterUnFoundURLPatternToHandler{
    [[self sharedIsntance] setUnFoundRoutesBlock:nil];
}

+ (void)deregisterURLPattern:(NSString *)URLPattern
{
    [[self sharedIsntance] removeURLPattern:URLPattern];
}

+ (void)openURL:(NSString *)URL
{
    [self openURL:URL completion:nil];
}

+ (void)openURL:(NSString *)URL completion:(void (^)(id result))completion
{
    [self openURL:URL withUserInfo:nil completion:completion];
}

+ (void)openURL:(NSString *)URL withUserInfo:(NSDictionary *)userInfo completion:(void (^)(id result))completion
{
    NSArray *tmpUrlArr=[[[self sharedIsntance] getRedirectURLPattern:URL] componentsSeparatedByString:@"?"];
    NSString *redirectURL=tmpUrlArr.count>0?tmpUrlArr[0]:URL;
    URL = redirectURL?redirectURL:URL;
    URL = [NSString stringWithFormat:@"%@?%@",URL,tmpUrlArr.count>1?tmpUrlArr[1]:@""];
    URL = [URL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *parameters = [[self sharedIsntance] extractParametersFromURL:URL];
    
    [parameters enumerateKeysAndObjectsUsingBlock:^(id key, NSString *obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSString class]]) {
            parameters[key] = [obj stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        }
    }];
    
    if (parameters) {
        NSDictionary *handlerDic = parameters[@"block"];
        
        if (completion) {
            parameters[ZYQRouterParameterCompletion] = completion;
        }
        if (userInfo) {
            parameters[ZYQRouterParameterUserInfo] = userInfo;
        }
        
        if (handlerDic) {
            if ([handlerDic[@"type"] isEqualToString:@"ZYQRouterHandler"]) {
                ZYQRouterHandler handler=handlerDic[@"block"];
                [parameters removeObjectForKey:@"block"];
                if (handler) {
                    handler(parameters);
                }
            }
            if ([handlerDic[@"type"] isEqualToString:@"ZYQRouterObjectHandler"]) {
                ZYQRouterObjectHandler handler=handlerDic[@"block"];
                if (handler) {
                    [parameters removeObjectForKey:@"block"];
                    id result = handler(parameters);
                    if (completion) {
                        completion(result);
                    }
                }
            }
        }
    }
}

+ (BOOL)canRedirectURL:(NSString*)URL{
    return [[self sharedIsntance] getRedirectURLPattern:URL] ? YES : NO;
}

+ (BOOL)canOpenURL:(NSString *)URL
{
    return [[self sharedIsntance] extractParametersFromURL:URL] ? YES : NO;
}

+ (NSString *)generateURLWithPattern:(NSString *)pattern parameters:(NSArray *)parameters
{
    NSInteger startIndexOfColon = 0;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    NSInteger parameterIndex = 0;
    
    for (int i = 0; i < pattern.length; i++) {
        NSString *character = [NSString stringWithFormat:@"%c", [pattern characterAtIndex:i]];
        if ([character isEqualToString:@":"]) {
            startIndexOfColon = i;
        }
        if (([@[@"/", @"?", @"&"] containsObject:character] || (i == pattern.length - 1 && startIndexOfColon) ) && startIndexOfColon) {
            if (i > (startIndexOfColon + 1)) {
                [items addObject:[NSString stringWithFormat:@"%@%@", [pattern substringWithRange:NSMakeRange(0, startIndexOfColon)], parameters[parameterIndex++]]];
                pattern = [pattern substringFromIndex:i];
                i = 0;
            }
            startIndexOfColon = 0;
        }
    }
    
    return [items componentsJoinedByString:@""];
}

+ (id)objectForURL:(NSString *)URL withUserInfo:(NSDictionary *)userInfo
{
    ZYQRouter *router = [ZYQRouter sharedIsntance];
    
    URL = [URL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *parameters = [router extractParametersFromURL:URL];
    NSDictionary *handlerDic = parameters[@"block"];
    
    if (handlerDic) {
        if (userInfo) {
            parameters[ZYQRouterParameterUserInfo] = userInfo;
        }
        if ([handlerDic[@"type"] isEqualToString:@"ZYQRouterObjectHandler"]) {
            ZYQRouterObjectHandler handler=handlerDic[@"block"];
            [parameters removeObjectForKey:@"block"];
            return handler(parameters);
            
        }
    }
    return nil;
}

+ (id)objectForURL:(NSString *)URL
{
    return [self objectForURL:URL withUserInfo:nil];
}


+ (void)registerURLPattern:(NSString *)URLPattern toObjectHandler:(ZYQRouterObjectHandler)handler
{
    [[self sharedIsntance] addURLPattern:URLPattern andObjectHandler:handler];
}


- (void)addRedirectURLPattern:(NSString *)URLPattern toURLPattern:(NSString*)newURLPattern{
    if (URLPattern) {
        if (newURLPattern) {
            [self.redirectRoutes setObject:newURLPattern forKey:URLPattern];
        }
        else{
            [self.redirectRoutes removeObjectForKey:URLPattern];
        }
    }
}

- (NSString*)getRedirectURLPattern:(NSString *)URLPattern{
    if (URLPattern) {
        NSString *redirectURL=[self getRedirectURLPattern:self.redirectRoutes[URLPattern]];
        if (redirectURL) {
            return redirectURL;
        }
        else{
            return URLPattern;
        }
    }
    return nil;
}

- (void)addURLPattern:(NSString *)URLPattern andHandler:(ZYQRouterHandler)handler
{
    NSMutableDictionary *subRoutes = [self addURLPattern:URLPattern];
    if (handler && subRoutes) {
        subRoutes[@"_"] = @{@"block":[handler copy],@"type":@"ZYQRouterHandler"};
    }
}

- (void)addURLPattern:(NSString *)URLPattern andObjectHandler:(ZYQRouterObjectHandler)handler
{
    NSMutableDictionary *subRoutes = [self addURLPattern:URLPattern];
    if (handler && subRoutes) {
        subRoutes[@"_"] = @{@"block":[handler copy],@"type":@"ZYQRouterObjectHandler"};
    }
}

- (NSMutableDictionary *)addURLPattern:(NSString *)URLPattern
{
    NSArray *pathComponents = [self pathComponentsFromURL:URLPattern];
    
    NSInteger index = 0;
    NSMutableDictionary* subRoutes = self.routes;
    
    while (index < pathComponents.count) {
        NSString* pathComponent = pathComponents[index];
        if (![subRoutes objectForKey:pathComponent]) {
            subRoutes[pathComponent] = [[NSMutableDictionary alloc] init];
        }
        subRoutes = subRoutes[pathComponent];
        index++;
    }
    return subRoutes;
}

#pragma mark - Target Action 安全调度 -

+ (void)addNotFoundHandler:(ZYQNotFoundTargetActionHandler)notFoundHandler targetName:(NSString*)targetName{
    if (!notFoundHandler) {
        return;
    }
    if (targetName==nil) {
        ((ZYQRouter*)[self sharedIsntance]).notFoundBlocks[@"_"]=[notFoundHandler copy];
    }
    else{
        ((ZYQRouter*)[self sharedIsntance]).notFoundBlocks[targetName]=[notFoundHandler copy];
    }
}

+ (void)removeTargetsCacheWithTargetName:(NSString*)targetName{
    [((ZYQRouter*)[self sharedIsntance]).targetsCache removeObjectForKey:targetName];
}

+ (void)removeTargetsCacheWithTargetNames:(NSArray*)targetNames{
    [((ZYQRouter*)[self sharedIsntance]).targetsCache removeObjectsForKeys:targetNames];
}

+ (void)removeAllTargetsCache{
    [((ZYQRouter*)[self sharedIsntance]).targetsCache removeAllObjects];
}

+ (id)getTargetsCacheWithTargetName:(NSString*)targetName{
    return [((ZYQRouter*)[self sharedIsntance]).targetsCache objectForKey:targetName];
}

+ (NSArray*)getTargetsCacheWithTargetNames:(NSArray*)targetNames{
    NSMutableArray *targetsResult=[[NSMutableArray alloc] init];
    for (NSString *targetName in targetNames) {
        [targetsResult addObject:[((ZYQRouter*)[self sharedIsntance]).targetsCache objectForKey:targetName]];
    }
    return [NSArray arrayWithArray:targetsResult];
}

+ (NSArray*)getAllTargetsCache{
    return ((ZYQRouter*)[self sharedIsntance]).targetsCache.allValues;
}


+ (id)performTarget:(NSString*)targetName action:(NSString*)actionName objects:(id)object1,...{
    NSMutableArray *objectsArr=[[NSMutableArray alloc] init];
    
    if (object1)
    {
        va_list argsList;
        [objectsArr addObject:object1];
        va_start(argsList, object1);
        id arg;
        while ((arg = va_arg(argsList, id)))
        {
            [objectsArr addObject:arg];
        }
        va_end(argsList);
    }
    
    return [self performTarget:targetName action:actionName shouldCacheTaget:NO objectsArr:[NSArray arrayWithArray:objectsArr]];
}

+ (id)performTarget:(NSString*)targetName action:(NSString*)actionName shouldCacheTaget:(BOOL)shouldCacheTaget objects:(id)object1,...{
    NSMutableArray *objectsArr=[[NSMutableArray alloc] init];
    
    if (object1)
    {
        va_list argsList;
        [objectsArr addObject:object1];
        va_start(argsList, object1);
        id arg;
        while ((arg = va_arg(argsList, id)))
        {
            [objectsArr addObject:arg];
        }
        va_end(argsList);
    }
    
    return [self performTarget:targetName action:actionName shouldCacheTaget:shouldCacheTaget objectsArr:[NSArray arrayWithArray:objectsArr]];
}

+ (id)performTarget:(NSString*)targetName action:(NSString*)actionName shouldCacheTaget:(BOOL)shouldCacheTaget objectsArr:(NSArray*)objectsArr{
    id target=((ZYQRouter*)[self sharedIsntance]).targetsCache[targetName];
    if (target==nil) {
        Class targetClass=NSClassFromString(targetName);
        
        target=[[targetClass alloc] init];
    }
    
    SEL action=NSSelectorFromString(actionName);
    ZYQNotFoundTargetActionHandler notFoundBlock = ((ZYQRouter*)[self sharedIsntance]).notFoundBlocks[targetName];
    if (!notFoundBlock) {
        notFoundBlock=((ZYQRouter*)[self sharedIsntance]).notFoundBlocks[@"_"];
    }
    
    if (target==nil) {
        if (notFoundBlock) {
            notFoundBlock(ZYQNotFoundHandlerError_NotFoundTarget,objectsArr);
        }
        return nil;
    }
    
    if (shouldCacheTaget) {
        ((ZYQRouter*)[self sharedIsntance]).targetsCache[targetName]=target;
    }
    
    if ([target respondsToSelector:action]) {
        return [target zyq_performSelector:action withObjectsArray:objectsArr];
    }
    else{
        SEL notFoundAction = NSSelectorFromString(@"notFound");
        
        if ([target respondsToSelector:notFoundAction]) {
            ZYQ_SuppressPerformSelectorLeakWarning(return [target performSelector:notFoundAction]);
        }
        else{
            if (notFoundBlock) {
                notFoundBlock(ZYQNotFoundHandlerError_NotFoundAction,objectsArr);
            }
        }
    }
    
    return nil;
}

#pragma mark - Utils

- (NSMutableDictionary *)extractParametersFromURL:(NSString *)url
{
    NSMutableDictionary* parameters = [NSMutableDictionary dictionary];
    
    parameters[ZYQRouterParameterURL] = url;
    
    NSMutableDictionary* subRoutes = self.routes;
    NSArray* pathComponents = [self pathComponentsFromURL:url];
    
    BOOL found = NO;
    
    // borrowed from HHRouter(https://github.com/Huohua/HHRouter)
    for (NSString* pathComponent in pathComponents) {
        
        // 对 key 进行排序，这样可以把 ~ 放到最后
        NSArray *subRoutesKeys =[subRoutes.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
            return [obj1 compare:obj2];
        }];
        
        for (NSString* key in subRoutesKeys) {
            if ([key isEqualToString:pathComponent] || [key isEqualToString:ZYQ_ROUTER_WILDCARD_CHARACTER]) {
                found = YES;
                subRoutes = subRoutes[key];
                break;
            } else if ([key hasPrefix:@":"]) {
                found = YES;
                subRoutes = subRoutes[key];
                parameters[[key substringFromIndex:1]] = pathComponent;
                break;
            }
        }
        // 如果没有找到该 pathComponent 对应的 handler，则以上一层的 handler 作为 fallback
        if (!found && !subRoutes[@"_"]) {
            if (_unFoundRoutesBlock) {
                parameters[@"block"] = _unFoundRoutesBlock;
                return parameters;
            }

            return nil;
        }
    }
    
    // Extract Params From Query.
    NSArray* pathInfo = [url componentsSeparatedByString:@"?"];
    if (pathInfo.count > 1) {
        NSString* parametersString = [pathInfo objectAtIndex:1];
        NSArray* paramStringArr = [parametersString componentsSeparatedByString:@"&"];
        for (NSString* paramString in paramStringArr) {
            NSArray* paramArr = [paramString componentsSeparatedByString:@"="];
            if (paramArr.count > 1) {
                NSString* key = [paramArr objectAtIndex:0];
                NSString* value = [[paramArr objectAtIndex:1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                parameters[key] = value;
            }
        }
    }
    
    if (subRoutes[@"_"]) {
        parameters[@"block"] = subRoutes[@"_"];
    }
    else{
        if (_unFoundRoutesBlock) {
            parameters[@"block"] = _unFoundRoutesBlock;
        }
    }
    return parameters;
}

- (void)removeURLPattern:(NSString *)URLPattern
{
    NSMutableArray *pathComponents = [NSMutableArray arrayWithArray:[self pathComponentsFromURL:URLPattern]];
    
    // 只删除该 pattern 的最后一级
    if (pathComponents.count >= 1) {
        // 假如 URLPattern 为 a/b/c, components 就是 @"a.b.c" 正好可以作为 KVC 的 key
        NSString *components = [pathComponents componentsJoinedByString:@"."];
        NSMutableDictionary *route = [self.routes valueForKeyPath:components];
        
        if (route.count >= 1) {
            NSString *lastComponent = [pathComponents lastObject];
            [pathComponents removeLastObject];
            
            // 有可能是根 key，这样就是 self.routes 了
            route = self.routes;
            if (pathComponents.count) {
                NSString *componentsWithoutLast = [pathComponents componentsJoinedByString:@"."];
                route = [self.routes valueForKeyPath:componentsWithoutLast];
            }
            [route removeObjectForKey:lastComponent];
        }
    }
}

- (NSArray*)pathComponentsFromURL:(NSString*)URL
{
    NSMutableArray *pathComponents = [NSMutableArray array];
    if ([URL rangeOfString:@"://"].location != NSNotFound) {
        NSArray *pathSegments = [URL componentsSeparatedByString:@"://"];
        // 如果 URL 包含协议，那么把协议作为第一个元素放进去
        [pathComponents addObject:pathSegments[0]];
        
        // 如果只有协议，那么放一个占位符
        if ((pathSegments.count >= 2 && ((NSString *)pathSegments[1]).length) || pathSegments.count < 2) {
            [pathComponents addObject:ZYQ_ROUTER_WILDCARD_CHARACTER];
        }
        
        URL = [URL substringFromIndex:[URL rangeOfString:@"://"].location + 3];
    }
    
    for (NSString *pathComponent in [[NSURL URLWithString:URL] pathComponents]) {
        if ([pathComponent isEqualToString:@"/"]) continue;
        if ([[pathComponent substringToIndex:1] isEqualToString:@"?"]) break;
        [pathComponents addObject:pathComponent];
    }
    return [pathComponents copy];
}

#pragma mark - Getter
- (NSMutableDictionary *)routes
{
    if (!_routes) {
        _routes = [[NSMutableDictionary alloc] init];
    }
    return _routes;
}

- (NSMutableDictionary *)redirectRoutes
{
    if (!_redirectRoutes) {
        _redirectRoutes = [[NSMutableDictionary alloc] init];
    }
    return _redirectRoutes;
}

- (NSMutableDictionary *)targetsCache
{
    if (!_targetsCache) {
        _targetsCache = [[NSMutableDictionary alloc] init];
    }
    return _targetsCache;
}

- (NSMutableDictionary *)notFoundBlocks
{
    if (!_notFoundBlocks) {
        _notFoundBlocks = [[NSMutableDictionary alloc] init];
    }
    return _notFoundBlocks;
}
@end

void * zyq_invokeSelectorObjects(NSString *className,NSString* selectorName,...){
    @try {
        Class inst=NSClassFromString(className);
        SEL sel = NSSelectorFromString(selectorName);

        NSMutableArray *objectsArr=[[NSMutableArray alloc] init];
        
        va_list argsList;
        va_start(argsList, selectorName);
        id arg;
        while ((arg = va_arg(argsList, id)))
        {
            [objectsArr addObject:arg];
        }
        va_end(argsList);
        
        void *result = nil;
        if (objectsArr.count<1) {
            void *(*objcMsgSend)(id, SEL) = (void *(*)(id, SEL)) objc_msgSend;

            result = objcMsgSend(inst, sel);
        }
        else if (objectsArr.count<2) {
            void *(*objcMsgSend)(id, SEL, id) = (void *(*)(id, SEL, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0]);
        }
        else if (objectsArr.count<3) {
            void *(*objcMsgSend)(id, SEL, id, id) = (void *(*)(id, SEL, id, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0] ,objectsArr[1]);
        }
        else if (objectsArr.count<4) {
            void *(*objcMsgSend)(id, SEL, id, id, id) = (void *(*)(id, SEL, id, id, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0] ,objectsArr[1] ,objectsArr[2]);
        }
        else if (objectsArr.count<5) {
            void *(*objcMsgSend)(id, SEL, id, id, id, id) = (void *(*)(id, SEL, id, id, id, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0] ,objectsArr[1] ,objectsArr[2] ,objectsArr[3]);
        }
        else if (objectsArr.count<6) {
            void *(*objcMsgSend)(id, SEL, id, id, id, id, id) = (void *(*)(id, SEL, id, id, id, id, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0] ,objectsArr[1] ,objectsArr[2] ,objectsArr[3] ,objectsArr[4]);
        }
        else if (objectsArr.count<7) {
            void *(*objcMsgSend)(id, SEL, id, id, id, id, id, id) = (void *(*)(id, SEL, id, id, id, id, id, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0] ,objectsArr[1] ,objectsArr[2] ,objectsArr[3] ,objectsArr[4] ,objectsArr[5]);
        }
        else if (objectsArr.count<8) {
            void *(*objcMsgSend)(id, SEL, id, id, id, id, id, id, id) = (void *(*)(id, SEL, id, id, id, id, id, id, id)) objc_msgSend;

            result = objcMsgSend(inst, sel ,objectsArr[0] ,objectsArr[1] ,objectsArr[2] ,objectsArr[3] ,objectsArr[4] ,objectsArr[5] ,objectsArr[6]);
        }
        
        return result;
    } @catch (NSException *exception) {
        return nil;
    } @finally {
        
    }
}

@implementation NSObject (ZYQRouter)

-(id)zyq_performSelector:(SEL)selector withObjects:(id)object1,... {
    NSMutableArray *objectsArr=[[NSMutableArray alloc] init];
    
    if (object1)
    {
        va_list argsList;
        [objectsArr addObject:object1];
        va_start(argsList, object1);
        id arg;
        while ((arg = va_arg(argsList, id)))
        {
            [objectsArr addObject:arg];
        }
        va_end(argsList);
    }
    
    return [self zyq_performSelector:selector withObjectsArray:[NSArray arrayWithArray:objectsArr]];
}

-(id)zyq_performSelector:(SEL)selector withObjectsArray:(NSArray *)objects {
    
    // 方法签名
    NSMethodSignature *signature = [[self class] instanceMethodSignatureForSelector:selector];
    if(signature == nil){
        [NSException raise:@"target error" format:@"%@方法找不到",NSStringFromSelector(selector)];
    }
    
    // 利用一个NSInvocation对象包装一次方法调用(方法调用者,方法名,方法参数,方法返回值)
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = self;
    invocation.selector = selector;
    
    // 设置参数
    NSInteger paramsCount = signature.numberOfArguments - 2; // 除self/_cmd以外的参数个数
    paramsCount = MIN(paramsCount, objects.count);
    
    
    for( NSInteger i = 0; i<paramsCount; i++) {
        id object = objects[i];
        if([object isKindOfClass:[NSNull class]]) continue;
        
        [invocation setArgument:&object atIndex:i+2];
    }
    
    // 调用方法
    [invocation invoke];
    
    // 获取返回值
    id returnValue = nil;
    if(signature.methodReturnLength) {
        // 有返回值类型,才去获得返回值
        [invocation getReturnValue:&returnValue];
    }
    
    return returnValue;
}

@end

@implementation UIResponder (ZYQRouter)

-(void)zyq_routerEventWithName:(NSString *)eventName userInfo:(id)userInfo{
    [[self nextResponder] zyq_routerEventWithName:eventName userInfo:userInfo];
}

@end
