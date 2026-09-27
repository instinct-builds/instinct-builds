// Separate-process AX client for the MUEW standalone. No editor headers or
// direct model calls: all reads and actions cross Accessibility IPC.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <cstdio>
#include <cstdlib>
#include <unistd.h>

static CFTypeRef Attribute(AXUIElementRef e, CFStringRef key) {
    CFTypeRef v=nullptr;
    AXError err=AXUIElementCopyAttributeValue(e,key,&v);
    return err==kAXErrorSuccess ? v : nullptr;
}
static NSString* String(AXUIElementRef e, CFStringRef key) {
    CFTypeRef v=Attribute(e,key);
    if (!v) return @"";
    NSString* text=CFGetTypeID(v)==CFStringGetTypeID() ? [(__bridge NSString*)v copy] : @"";
    CFRelease(v); return text;
}
static NSArray* Children(AXUIElementRef e) {
    CFTypeRef v=Attribute(e,kAXChildrenAttribute);
    if (!v) return @[];
    NSArray* result=CFGetTypeID(v)==CFArrayGetTypeID() ? [(__bridge NSArray*)v copy] : @[];
    CFRelease(v); return result;
}
static AXUIElementRef Find(AXUIElementRef root, NSString* role, NSString* label, int depth=0) {
    if (depth>10) return nullptr;
    if ([String(root,kAXRoleAttribute) isEqualToString:role] &&
        (!label || [String(root,kAXTitleAttribute) isEqualToString:label] ||
         [String(root,kAXDescriptionAttribute) isEqualToString:label])) return (AXUIElementRef)CFRetain(root);
    for (id obj in Children(root)) {
        AXUIElementRef found=Find((__bridge AXUIElementRef)obj,role,label,depth+1);
        if (found) return found;
    }
    return nullptr;
}
static void Log(const char* what, AXError code) { printf("AX IPC %s: %d\n",what,(int)code); fflush(stdout); }
int main(int argc,const char** argv) {
 @autoreleasepool {
    if (argc!=2) { fprintf(stderr,"usage: ax_ipc_client PID\n"); return 2; }
    pid_t pid=(pid_t)atoi(argv[1]);
    printf("AX IPC trusted=%d target_pid=%d\n",(int)AXIsProcessTrusted(),(int)pid);
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    AXError err=kAXErrorSuccess; CFTypeRef windows=nullptr;
    for (int n=0;n<20;++n) {
        err=AXUIElementCopyAttributeValue(app,kAXWindowsAttribute,&windows);
        if (err==kAXErrorSuccess && windows && CFGetTypeID(windows)==CFArrayGetTypeID() && CFArrayGetCount((CFArrayRef)windows)>0) break;
        if (windows) { CFRelease(windows); windows=nullptr; }
        usleep(250000);
    }
    Log("windows",err);
    if (err==kAXErrorAPIDisabled || err==kAXErrorNotImplemented || err==kAXErrorCannotComplete || !AXIsProcessTrusted()) {
        puts("AX IPC BLOCKED: external client has no trusted Accessibility path; no VoiceOver claim");
        if (windows) CFRelease(windows); CFRelease(app); return 77;
    }
    if (err!=kAXErrorSuccess || !windows || CFArrayGetCount((CFArrayRef)windows)==0) { if (windows) CFRelease(windows); CFRelease(app); return 1; }
    AXUIElementRef window=(AXUIElementRef)CFArrayGetValueAtIndex((CFArrayRef)windows,0);
    NSString* windowTitle=String(window,kAXTitleAttribute);
    printf("AX IPC window=%s\n",windowTitle.UTF8String);
    AXUIElementRef search=Find(window,@"AXTextField",nil);
    AXUIElementRef list=Find(window,@"AXList",@"Preset results");
    printf("AX IPC native_search=%d named_list=%d\n",!!search,!!list);
    bool ok=(search != nullptr) && (list != nullptr) && [windowTitle isEqualToString:@"MUEW"];
    if (list) {
        NSArray* rows=Children(list);
        NSString* first=rows.count ? String((__bridge AXUIElementRef)rows[0],kAXDescriptionAttribute) : @"";
        if (!first.length && rows.count) first=String((__bridge AXUIElementRef)rows[0],kAXTitleAttribute);
        if (rows.count) {
            AXUIElementRef firstRow=(__bridge AXUIElementRef)rows[0];
            CFArrayRef attributes=nullptr;
            AXError attributesError=AXUIElementCopyAttributeNames(firstRow,&attributes);
            printf("AX IPC row role=%s title=%s description=%s value=%s help=%s names_error=%d\n",
                   String(firstRow,kAXRoleAttribute).UTF8String,
                   String(firstRow,kAXTitleAttribute).UTF8String,
                   String(firstRow,kAXDescriptionAttribute).UTF8String,
                   String(firstRow,kAXValueAttribute).UTF8String,
                   String(firstRow,kAXHelpAttribute).UTF8String,(int)attributesError);
            if (attributes) {
                for (id key in (__bridge NSArray*)attributes) printf("AX IPC row attribute=%s\n",[key UTF8String]);
                CFRelease(attributes);
            }
        }
        CFTypeRef frame=Attribute(list,kAXPositionAttribute);
        printf("AX IPC rows=%lu first=%s frame=%d\n",(unsigned long)rows.count,first.UTF8String,!!frame);
        ok=ok && rows.count>1 && [first containsString:@"1 of 108"] &&
           [first containsString:@"proposed: no"] && [first containsString:@"loaded: no"] && !!frame;
        if (frame) CFRelease(frame);
        if (ok) {
            AXUIElementRef row=(__bridge AXUIElementRef)rows[1];
            NSString* chosen=String(row,kAXDescriptionAttribute);
            if (!chosen.length) chosen=String(row,kAXTitleAttribute);
            err=AXUIElementPerformAction(row,kAXPressAction);
            Log("row_press",err);
            NSArray* after=Children(list);
            NSString* loaded=after.count>1 ? String((__bridge AXUIElementRef)after[1],kAXDescriptionAttribute) : @"";
            if (!loaded.length && after.count>1) loaded=String((__bridge AXUIElementRef)after[1],kAXTitleAttribute);
            printf("AX IPC press_selected=%s after=%s\n",chosen.UTF8String,loaded.UTF8String);
            ok=ok && err==kAXErrorSuccess && [loaded containsString:@"loaded: yes"];
        }
    }
    if (search) CFRelease(search); if (list) CFRelease(list);
    CFRelease(windows); CFRelease(app);
    printf("AX IPC %s\n",ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
 }
}
