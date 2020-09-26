//  Copyright 2015 Microsoft Corporation
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//


#import "ODAuthenticationViewController.h"
#import "ODAuthHelper.h"
#import "ODAuthConstants.h"
#import <WebKit/WebKit.h>

#define kRequestTimeoutDefault  60

@interface ODAuthenticationViewController() <WKNavigationDelegate>

@property WKWebView *webView;

@property NSURLRequest *initialRequest;
@property (strong, nonatomic) ODEndURLCompletion successCompletion;
@property (strong, nonatomic) NSURL *endURL;

@property (strong, nonatomic) NSTimer *timer;
@property (nonatomic) BOOL isComplete;

@end

@implementation ODAuthenticationViewController

- (instancetype)initWithStartURL:(NSURL *)startURL
                          endURL:(NSURL *)endURL
                         success:(ODEndURLCompletion)sucessCompletion
{
    self = [super init];
    if (self){
        _endURL = endURL;
        _initialRequest = [NSURLRequest requestWithURL:startURL];
        _successCompletion = sucessCompletion;
        _requestTimeout = kRequestTimeoutDefault;
        _isComplete = NO;
    }
    return self;
}

- (void)cancel
{
    if (!self.isComplete)
    {
        [self.timer invalidate];
        self.timer = nil;
        self.isComplete = YES;
        
        NSError *cancelError = [NSError errorWithDomain:OD_AUTH_ERROR_DOMAIN code:ODAuthCanceled userInfo:@{}];
        if (self.successCompletion){
            self.successCompletion(nil, cancelError);
        }
    }
}

- (void)loadInitialRequest
{
    [self.webView loadRequest:self.initialRequest];
}

- (void)redirectWithStartURL:(NSURL *)startURL
                      endURL:(NSURL *)endURL
                      success:(ODEndURLCompletion)successCompletion
{
    self.endURL = endURL;
    self.successCompletion = successCompletion;
    self.initialRequest = [NSURLRequest requestWithURL:startURL];
    self.isComplete = NO;
    [self.webView loadRequest:self.initialRequest];
}

- (void)loadView
{
    self.webView = [[WKWebView alloc] init];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.view = self.webView;
    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                target:self
                                                                                action:@selector(cancel)];
    self.navigationController.topViewController.navigationItem.leftBarButtonItem = cancel;
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.webView loadRequest:self.initialRequest];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.webView stopLoading];
    self.webView.navigationDelegate = nil;
    [super viewWillDisappear:animated];
}

#pragma mark - WKWebViewDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.requestTimeout target:self selector:@selector(failWithTimeout) userInfo:nil repeats:NO];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [self.timer invalidate];
    self.timer = nil;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if ([[[navigationAction.request.URL absoluteString] lowercaseString] hasPrefix:[[self.endURL absoluteString] lowercaseString]]) {
        self.isComplete = YES;
        [self.timer invalidate];
        self.timer = nil;

        self.successCompletion(navigationAction.request.URL, nil);
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self.timer invalidate];
    self.timer = nil;
    
    if (NSURLErrorCancelled == error.code)
    {
        //This is a common error that webview generates and could be ignored.
        //See this thread for details: https://discussions.apple.com/thread/1727260
        return;
    }
    
    if([error.domain isEqual:@"WebKitErrorDomain"]){
        return;
    }
    
    // Ignore failures that are triggered after we have found the end URL
    if (self.isComplete)
    {
        //We expect to get an error here, as we intentionally fail to navigate to the final redirect URL.
        return;
    }
    
    if (self.successCompletion) {
        self.successCompletion(nil, error);
    }
}

- (void)failWithTimeout
{
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    [self webView:self.webView didFailNavigation:nil withError:error];
}

@end
