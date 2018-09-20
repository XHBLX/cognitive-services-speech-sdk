//
// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE.md file in the project root for full license information.
//

#import "speechapi_private.h"

struct SpeechEventHandlerHelper
{
    SPXSpeechRecognizer *recognizer;
    SpeechRecoSharedPtr recoImpl;

    SpeechEventHandlerHelper(SPXSpeechRecognizer *reco, SpeechRecoSharedPtr recoImpl)
    {
        recognizer = reco;
        this->recoImpl = recoImpl;
    }
    
    void addRecognizedEventHandler()
    {
        LogDebug(@"Add RecognizedEventHandler");
        recoImpl->Recognized.Connect([this] (const SpeechImpl::SpeechRecognitionEventArgs& e)
            {
                SPXSpeechRecognitionEventArgs *eventArgs = [[SPXSpeechRecognitionEventArgs alloc] init: e];
                [recognizer onRecognizedEvent: eventArgs];
            });
    }
    
    void addRecognizingEventHandler()
    {
        LogDebug(@"Add RecognizingEventHandler");
        recoImpl->Recognizing.Connect([this] (const SpeechImpl::SpeechRecognitionEventArgs& e)
            {
                SPXSpeechRecognitionEventArgs *eventArgs = [[SPXSpeechRecognitionEventArgs alloc] init: e];
                [recognizer onRecognizingEvent: eventArgs];
            });
    }

    void addCanceledEventHandler()
    {
        LogDebug(@"Add CanceledEventHandler");
        recoImpl->Canceled.Connect([this] (const SpeechImpl::SpeechRecognitionCanceledEventArgs& e)
            {
                SPXSpeechRecognitionCanceledEventArgs *eventArgs = [[SPXSpeechRecognitionCanceledEventArgs alloc] init:e];
                [recognizer onCanceledEvent: eventArgs];
            });
    }

    void addSessionStartedEventHandler()
    {
        LogDebug(@"Add SessionStartedEventHandler");
        recoImpl->SessionStarted.Connect([this] (const SpeechImpl::SessionEventArgs& e)
            {
                SPXSessionEventArgs *eventArgs = [[SPXSessionEventArgs alloc] init:e];
                [recognizer onSessionStartedEvent: eventArgs];
            });
    }
    
    void addSessionStoppedEventHandler()
    {
        LogDebug(@"Add SessionStoppedEventHandler");
        recoImpl->SessionStopped.Connect([this] (const SpeechImpl::SessionEventArgs& e)
            {
                SPXSessionEventArgs *eventArgs = [[SPXSessionEventArgs alloc] init:e];
                [recognizer onSessionStoppedEvent: eventArgs];
            });
    }
    
    void addSpeechStartDetectedEventHandler()
    {
        LogDebug(@"Add SpeechStartDetectedEventHandler");
        recoImpl->SpeechStartDetected.Connect([this] (const SpeechImpl::RecognitionEventArgs& e)
            {
                SPXRecognitionEventArgs *eventArgs = [[SPXRecognitionEventArgs alloc] init:e];
                [recognizer onSpeechStartDetectedEvent: eventArgs];
            });
    }
    
    void addSpeechEndDetectedEventHandler()
    {
        LogDebug(@"Add SpeechStopDetectedEventHandler");
        recoImpl->SpeechEndDetected.Connect([this] (const SpeechImpl::RecognitionEventArgs& e)
            {
                SPXRecognitionEventArgs *eventArgs = [[SPXRecognitionEventArgs alloc] init:e];
                [recognizer onSpeechEndDetectedEvent: eventArgs];
            });
    }
};

@implementation SPXSpeechRecognizer
{
    SpeechRecoSharedPtr speechRecoImpl;
    dispatch_queue_t dispatchQueue;
    
    NSMutableArray *recognizedEventHandlerList;
    NSLock *recognizedLock;
    NSMutableArray *recognizingEventHandlerList;
    NSLock *recognizingLock;
    NSMutableArray *canceledEventHandlerList;
    NSLock *canceledLock;
    struct SpeechEventHandlerHelper *eventImpl;
    
    RecognizerPropertyCollection *propertyCollection;
}

- (instancetype)init:(SPXSpeechConfiguration *)speechConfiguration {
     try {
        auto recoImpl = SpeechImpl::SpeechRecognizer::FromConfig([speechConfiguration getHandle]);
        if (recoImpl == nullptr)
            return nil;
        return [self initWithImpl:recoImpl];
    }
    catch (...) {
        // Todo: better error handling.
        NSLog(@"Exception caught when creating SPXSpeechRecognizer in core.");
    }
    return nil;
}


- (instancetype)initWithSpeechConfiguration:(SPXSpeechConfiguration *)speechConfiguration audioConfiguration:(SPXAudioConfiguration *)audioConfiguration {
    try {
        auto recoImpl = SpeechImpl::SpeechRecognizer::FromConfig([speechConfiguration getHandle], [audioConfiguration getHandle]);
        if (recoImpl == nullptr)
            return nil;
        return [self initWithImpl:recoImpl];
    }
    catch (...) {
        // Todo: better error handling.
        NSLog(@"Exception caught when creating SPXSpeechRecognizer in core.");
    }
    return nil;
}

- (instancetype)initWithImpl:(SpeechRecoSharedPtr)recoHandle
{
    self = [super initFrom:recoHandle withParameters:&recoHandle->Properties];
    self->speechRecoImpl = recoHandle;
    if (!self || speechRecoImpl == nullptr) {
        return nil;
    }
    else
    {
        dispatchQueue = dispatch_queue_create("com.microsoft.cognitiveservices.speech", nil);
        recognizedEventHandlerList = [NSMutableArray array];
        recognizingEventHandlerList = [NSMutableArray array];
        canceledEventHandlerList = [NSMutableArray array];
        recognizedLock = [[NSLock alloc] init];
        recognizingLock = [[NSLock alloc] init];
        canceledLock = [[NSLock alloc] init];
        
        eventImpl = new SpeechEventHandlerHelper(self, speechRecoImpl);
        [super setDispatchQueue: dispatchQueue];
        eventImpl->addRecognizingEventHandler();
        eventImpl->addRecognizedEventHandler();
        eventImpl->addCanceledEventHandler();
        eventImpl->addSessionStartedEventHandler();
        eventImpl->addSessionStoppedEventHandler();
        eventImpl->addSpeechStartDetectedEventHandler();
        eventImpl->addSpeechEndDetectedEventHandler();

        return self;
    }
}

- (void)setAuthorizationToken: (NSString *)token
{
    speechRecoImpl->SetAuthorizationToken([token string]);
}

- (NSString *)authorizationToken
{
    return [NSString stringWithString:speechRecoImpl->GetAuthorizationToken()];
}

- (NSString *)endpointId
{
    return [NSString stringWithString:speechRecoImpl->GetEndpointId()];
}

- (SPXSpeechRecognitionResult *)recognizeOnce
{
    SPXSpeechRecognitionResult *result = nil;
    
    if (speechRecoImpl == nullptr) {
        result = [[SPXSpeechRecognitionResult alloc] initWithError: @"SPXRecognizer has been closed."];
        return result;
    }
    
    try {
        std::shared_ptr<SpeechImpl::SpeechRecognitionResult> resultImpl = speechRecoImpl->RecognizeOnceAsync().get();
        if (resultImpl == nullptr) {
            result = [[SPXSpeechRecognitionResult alloc] initWithError: @"No result available."];
        }
        else
        {
            result = [[SPXSpeechRecognitionResult alloc] init: resultImpl];
        }
    }
    catch (...) {
        // Todo: better error handling
        NSLog(@"exception caught");
        result = [[SPXSpeechRecognitionResult alloc] initWithError: @"Runtime Exception"];
    }
    
    return result;
}

- (void)recognizeOnceAsync:(void (^)(SPXSpeechRecognitionResult *))resultReceivedHandler
{
    SPXSpeechRecognitionResult *result = nil;
    if (speechRecoImpl == nullptr) {
        result = [[SPXSpeechRecognitionResult alloc] initWithError: @"SPXRecognizer has been closed."];
        dispatch_async(dispatchQueue, ^{
            resultReceivedHandler(result);
        });
        return;
    }
    
    try {
        std::shared_ptr<SpeechImpl::SpeechRecognitionResult> resultImpl = speechRecoImpl->RecognizeOnceAsync().get();
        if (resultImpl == nullptr) {
            result = [[SPXSpeechRecognitionResult alloc] initWithError: @"No result available."];
        }
        else
        {
            result = [[SPXSpeechRecognitionResult alloc] init: resultImpl];
        }
    }
    catch (...) {
        // Todo: better error handling
        NSLog(@"exception caught");
        result = [[SPXSpeechRecognitionResult alloc] initWithError: @"Runtime Exception"];
    }
    
    dispatch_async(dispatchQueue, ^{
        resultReceivedHandler(result);
    });
}

- (void)startContinuousRecognition
{
    if (speechRecoImpl == nullptr) {
        // Todo: return error?
        NSLog(@"SPXRecognizer handle is null");
        return;
    }
    
    try {
        speechRecoImpl->StartContinuousRecognitionAsync().get();
    }
    catch (...) {
        // Todo: better error handling
        NSLog(@"exception caught");
    }
}

- (void)stopContinuousRecognition
{
    if (speechRecoImpl == nullptr) {
        // Todo: return error?
        NSLog(@"SPXRecognizer handle is null");
        return;
    }
    
    try {
        speechRecoImpl->StopContinuousRecognitionAsync().get();
    }
    catch (...) {
        // Todo: better error handling
        NSLog(@"exception caught");
    }
}

- (void)onRecognizedEvent:(SPXSpeechRecognitionEventArgs *)eventArgs
{
    LogDebug(@"OBJC: onRecognizedEvent");
    NSArray* workCopyOfList;
    [recognizedLock lock];
    workCopyOfList = [NSArray arrayWithArray:recognizedEventHandlerList];
    [recognizedLock unlock];
    for (id handle in workCopyOfList) {
        dispatch_async(dispatchQueue, ^{
            ((SPXSpeechRecognitionEventHandler)handle)(self, eventArgs);
        });
    }
}

- (void)onRecognizingEvent:(SPXSpeechRecognitionEventArgs *)eventArgs
{
    LogDebug(@"OBJC: onRecognizingEvent");
    NSArray* workCopyOfList;
    [recognizingLock lock];
    workCopyOfList = [NSArray arrayWithArray:recognizingEventHandlerList];
    [recognizingLock unlock];
    for (id handle in workCopyOfList) {
        dispatch_async(dispatchQueue, ^{
            ((SPXSpeechRecognitionEventHandler)handle)(self, eventArgs);
        });
    }
}

- (void)onCanceledEvent:(SPXSpeechRecognitionCanceledEventArgs *)eventArgs
{
    LogDebug(@"OBJC: onCanceledEvent");
    NSArray* workCopyOfList;
    [canceledLock lock];
    workCopyOfList = [NSArray arrayWithArray:canceledEventHandlerList];
    [canceledLock unlock];
    for (id handle in workCopyOfList) {
        dispatch_async(dispatchQueue, ^{
            ((SPXSpeechRecognitionCanceledEventHandler)handle)(self, eventArgs);
        });
    }
}

- (void)addRecognizedEventHandler:(SPXSpeechRecognitionEventHandler)eventHandler
{
    [recognizedLock lock];
    [recognizedEventHandlerList addObject:eventHandler];
    [recognizedLock unlock];
    return;
}

- (void)addRecognizingEventHandler:(SPXSpeechRecognitionEventHandler)eventHandler
{
    [recognizingLock lock];
    [recognizingEventHandlerList addObject:eventHandler];
    [recognizingLock unlock];
    return;
}

- (void)addCanceledEventHandler:(SPXSpeechRecognitionCanceledEventHandler)eventHandler
{
    [canceledLock lock];
    [canceledEventHandlerList addObject:eventHandler];
    [canceledLock unlock];
    return;
}

@end
