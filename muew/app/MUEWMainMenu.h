// MUEWMainMenu.h - the standalone's menu bar (0.98.0). Built here, not inline in
// the app delegate, so the focus host can inspect exactly what the app installs.
// Edit > Undo / Redo / Revert use the responder chain: the editor view handles
// them for sound edits, a focused text field handles them for its own text.
#pragma once
#import <AppKit/AppKit.h>

static NSMenuItem* MUEWMenuItem(NSMenu* m, NSString* title, SEL action, NSString* key,
                                NSEventModifierFlags mods = NSEventModifierFlagCommand) {
    NSMenuItem* it = [m addItemWithTitle:title action:action keyEquivalent:key];
    it.keyEquivalentModifierMask = mods;
    return it;
}

// Items: [0] MUEW, [1] File, [2] Edit, [3] Window.
static NSMenu* MUEWMakeMainMenu() {
    NSMenu* bar = [NSMenu new];
    NSMenuItem* appItem = [NSMenuItem new]; [bar addItem:appItem];
    NSMenu* app = [[NSMenu alloc] initWithTitle:@"MUEW"]; appItem.submenu = app;
    MUEWMenuItem(app, @"About MUEW", @selector(orderFrontStandardAboutPanel:), @"", 0);
    [app addItem:[NSMenuItem separatorItem]];
    MUEWMenuItem(app, @"Hide MUEW", @selector(hide:), @"h");
    MUEWMenuItem(app, @"Hide Others", @selector(hideOtherApplications:), @"h", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    MUEWMenuItem(app, @"Show All", @selector(unhideAllApplications:), @"", 0);
    [app addItem:[NSMenuItem separatorItem]];
    MUEWMenuItem(app, @"Quit MUEW", @selector(terminate:), @"q");

    NSMenuItem* fileItem = [NSMenuItem new]; [bar addItem:fileItem]; // 0.114.0: the sound file actions that were only buttons
    NSMenu* file = [[NSMenu alloc] initWithTitle:@"File"]; fileItem.submenu = file;
    MUEWMenuItem(file, @"Save Sound\u2026", @selector(saveSound:), @"s");
    MUEWMenuItem(file, @"Open Sound\u2026", @selector(openSound:), @"o");
    [file addItem:[NSMenuItem separatorItem]];
    MUEWMenuItem(file, @"Export Sound\u2026", @selector(exportSound:), @"e", NSEventModifierFlagCommand | NSEventModifierFlagShift);

    NSMenuItem* editItem = [NSMenuItem new]; [bar addItem:editItem];
    NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"]; editItem.submenu = edit;
    MUEWMenuItem(edit, @"Undo", @selector(undo:), @"z");
    MUEWMenuItem(edit, @"Redo", @selector(redo:), @"z", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    MUEWMenuItem(edit, @"Revert to Loaded Sound", @selector(revertSound:), @"", 0);
    [edit addItem:[NSMenuItem separatorItem]];
    MUEWMenuItem(edit, @"Cut", @selector(cut:), @"x");
    MUEWMenuItem(edit, @"Copy", @selector(copy:), @"c");
    MUEWMenuItem(edit, @"Paste", @selector(paste:), @"v");
    MUEWMenuItem(edit, @"Select All", @selector(selectAll:), @"a");
    [edit addItem:[NSMenuItem separatorItem]];
    MUEWMenuItem(edit, @"Find Sound", @selector(findSound:), @"f"); // 0.115.0: Cmd-F opens the browser with the search field active
    [edit addItem:[NSMenuItem separatorItem]];
    MUEWMenuItem(edit, @"All Notes Off", @selector(panic:), @".");  // 0.109.0: Cmd-. releases every sounding note

    NSMenuItem* winItem = [NSMenuItem new]; [bar addItem:winItem];
    NSMenu* win = [[NSMenu alloc] initWithTitle:@"Window"]; winItem.submenu = win;
    MUEWMenuItem(win, @"Minimize", @selector(performMiniaturize:), @"m");
    MUEWMenuItem(win, @"Close", @selector(performClose:), @"w");
    return bar;
}
