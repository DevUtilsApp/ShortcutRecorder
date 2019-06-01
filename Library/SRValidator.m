//
//  Copyright 2006 ShortcutRecorder Contributors
//  CC BY 3.0
//

#import "SRCommon.h"
#import "SRKeyCodeTransformer.h"
#import "SRShortcut.h"

#import "SRValidator.h"


@implementation SRValidator

- (instancetype)initWithDelegate:(NSObject<SRValidatorDelegate> *)aDelegate
{
    self = [super init];

    if (self)
    {
        _delegate = aDelegate;
    }

    return self;
}

- (instancetype)init
{
    return [self initWithDelegate:nil];
}


#pragma mark Methods

- (BOOL)validateShortcut:(SRShortcut *)aShortcut error:(NSError * __autoreleasing *)outError
{
    if (![self validateShortcutAgainstDelegate:aShortcut error:outError])
        return NO;
    else if ((![self.delegate respondsToSelector:@selector(shortcutValidatorShouldCheckSystemShortcuts:)] ||
              [self.delegate shortcutValidatorShouldCheckSystemShortcuts:self]) &&
             ![self validateShortcutAgainstSystemShortcuts:aShortcut error:outError])
    {
        return NO;
    }
    else if ((![self.delegate respondsToSelector:@selector(shortcutValidatorShouldCheckMenu:)] ||
              [self.delegate shortcutValidatorShouldCheckMenu:self]) &&
             ![self validateShortcut:aShortcut againstMenu:NSApp.mainMenu error:outError])
    {
        return NO;
    }
    else
        return YES;
}

- (BOOL)validateShortcutAgainstDelegate:(SRShortcut *)aShortcut error:(NSError * __autoreleasing *)outError
{
    if (self.delegate)
    {
        NSString *delegateReason = nil;
        if (([self.delegate respondsToSelector:@selector(shortcutValidator:isShortcutValid:reason:)] &&
             ![self.delegate shortcutValidator:self isShortcutValid:aShortcut reason:&delegateReason]) ||
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            ([self.delegate respondsToSelector:@selector(shortcutValidator:isKeyCode:andFlagsTaken:reason:)] &&
             [self.delegate shortcutValidator:self isKeyCode:aShortcut.keyCode andFlagsTaken:aShortcut.modifierFlags reason:&delegateReason]))
#pragma clang diagnostic pop

        {
            if (outError)
            {
                BOOL isASCIIOnly = YES;

                if ([self.delegate respondsToSelector:@selector(shortcutValidatorShouldUseASCIIStringForKeyCodes:)])
                    isASCIIOnly = [self.delegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];

                NSString *shortcut = [aShortcut readableStringRepresentation:isASCIIOnly];
                NSString *failureReason = [NSString stringWithFormat:SRLoc(@"The key combination \"%@\" can't be used!"), shortcut];
                NSString *description = nil;

                if (delegateReason.length)
                    description = [NSString stringWithFormat:SRLoc(@"The key combination \"%@\" can't be used because %@."), shortcut, delegateReason];
                else
                    description = [NSString stringWithFormat:SRLoc(@"The key combination \"%@\" is already in use."), shortcut];

                NSDictionary *userInfo = @{
                    NSLocalizedFailureReasonErrorKey : failureReason,
                    NSLocalizedDescriptionKey: description
               };

                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }

            return NO;
        }
    }

    return YES;
}

- (BOOL)validateShortcutAgainstSystemShortcuts:(SRShortcut *)aShortcut error:(NSError * __autoreleasing *)outError
{
    CFArrayRef s = NULL;
    OSStatus err = CopySymbolicHotKeys(&s);

    if (err != noErr)
    {
#ifdef DEBUG
        NSLog(@"WARNING: Unable to read System Shortcuts: %d.", err);
#endif
        return NO;
    }

    NSArray *symbolicHotKeys = (NSArray *)CFBridgingRelease(s);

    for (NSDictionary *symbolicHotKey in symbolicHotKeys)
    {
        if ((__bridge CFBooleanRef)symbolicHotKey[(__bridge NSString *)kHISymbolicHotKeyEnabled] != kCFBooleanTrue)
            continue;

        unsigned short symbolicHotKeyCode = [symbolicHotKey[(__bridge NSString *)kHISymbolicHotKeyCode] integerValue];

        if (symbolicHotKeyCode == aShortcut.keyCode)
        {
            UInt32 symbolicHotKeyFlags = [symbolicHotKey[(__bridge NSString *)kHISymbolicHotKeyModifiers] unsignedIntValue];
            symbolicHotKeyFlags &= SRCarbonModifierFlagsMask;

            if (SRCarbonToCocoaFlags(symbolicHotKeyFlags) == aShortcut.modifierFlags)
            {
                if (outError)
                {
                    BOOL isASCIIOnly = YES;

                    if ([self.delegate respondsToSelector:@selector(shortcutValidatorShouldUseASCIIStringForKeyCodes:)])
                        isASCIIOnly = [self.delegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];

                    NSString *shortcut = [aShortcut readableStringRepresentation:isASCIIOnly];
                    NSString *failureReason = [NSString stringWithFormat:
                                               SRLoc(@"The key combination \"%@\" can't be used!"),
                                               shortcut];
                    NSString *description = [NSString stringWithFormat:
                                             SRLoc(@"The key combination \"%@\" can't be used because it's already used by a system-wide keyboard shortcut. If you really want to use this key combination, most shortcuts can be changed in the Keyboard panel in System Preferences."),
                                             shortcut];
                    NSDictionary *userInfo = @{
                        NSLocalizedFailureReasonErrorKey: failureReason,
                        NSLocalizedDescriptionKey: description
                    };
                    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
                }

                return NO;
            }
        }
    }

    return YES;
}

- (BOOL)validateShortcut:(SRShortcut *)aShortcut againstMenu:(NSMenu *)aMenu error:(NSError * __autoreleasing *)outError
{
    for (NSMenuItem *menuItem in aMenu.itemArray)
    {
        if (menuItem.hasSubmenu && ![self validateShortcut:aShortcut againstMenu:menuItem.submenu error:outError])
            return NO;

        NSString *keyEquivalent = menuItem.keyEquivalent;

        if (!keyEquivalent.length)
            continue;

        NSEventModifierFlags keyEquivalentModifierMask = menuItem.keyEquivalentModifierMask;

        if ([aShortcut isEqualToKeyEquivalent:keyEquivalent withModifierFlags:keyEquivalentModifierMask])
        {
            if (outError)
            {
                BOOL isASCIIOnly = YES;

                if ([self.delegate respondsToSelector:@selector(shortcutValidatorShouldUseASCIIStringForKeyCodes:)])
                    isASCIIOnly = [self.delegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];

                NSString *shortcut = [aShortcut readableStringRepresentation:isASCIIOnly];
                NSString *failureReason = [NSString stringWithFormat:SRLoc(@"The key combination \"%@\" can't be used!"), shortcut];
                NSString *description = [NSString stringWithFormat:SRLoc(@"The key combination \"%@\" can't be used because it's already used by the menu item \"%@\"."), shortcut, menuItem.SR_path];
                NSDictionary *userInfo = @{
                    NSLocalizedFailureReasonErrorKey: failureReason,
                    NSLocalizedDescriptionKey: description
                };
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }

            return NO;
        }
    }

    return YES;
}


#pragma mark SRRecorderControlDelegate

- (BOOL)recorderControl:(SRRecorderControl *)aRecorder canRecordShortcut:(SRShortcut *)aShortcut
{
    NSError *error = nil;
    BOOL isValid = [self validateShortcut:aShortcut error:&error];

    if (!isValid)
    {
        if (aRecorder.window)
        {
            [aRecorder presentError:error
                     modalForWindow:aRecorder.window
                           delegate:nil
                 didPresentSelector:NULL
                        contextInfo:NULL];
        }
        else
            [aRecorder presentError:error];
    }

    return isValid;
}


#pragma mark Deprecated

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (BOOL)isKeyCode:(unsigned short)aKeyCode andFlagsTaken:(NSEventModifierFlags)aFlags error:(NSError * __autoreleasing *)outError;
{
    return ![self validateShortcut:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] error:outError];
}

- (BOOL)isKeyCode:(unsigned short)aKeyCode andFlagTakenInDelegate:(NSEventModifierFlags)aFlags error:(NSError * __autoreleasing *)outError
{
    return ![self validateShortcutAgainstDelegate:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] error:outError];
}

- (BOOL)isKeyCode:(unsigned short)aKeyCode andFlagsTakenInSystemShortcuts:(NSEventModifierFlags)aFlags error:(NSError * __autoreleasing *)outError
{
    return ![self validateShortcutAgainstSystemShortcuts:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] error:outError];
}

- (BOOL)isKeyCode:(unsigned short)aKeyCode andFlags:(NSEventModifierFlags)aFlags takenInMenu:(NSMenu *)aMenu error:(NSError * __autoreleasing *)outError
{
    return ![self validateShortcut:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] againstMenu:aMenu error:outError];
}

#pragma clang diagnostic pop

@end


@implementation NSMenuItem (SRValidator)

- (NSString *)SR_path
{
    NSMutableArray *items = [NSMutableArray array];
    static const NSUInteger Limit = 1000;
    static const NSString *Delimeter = @" → ";
    NSMenuItem *currentMenuItem = self;
    NSUInteger i = 0;

    do
    {
        [items insertObject:currentMenuItem atIndex:0];
        currentMenuItem = currentMenuItem.parentItem;
        ++i;
    }
    while (currentMenuItem && i < Limit);

    NSMutableString *path = [NSMutableString string];

    for (NSMenuItem *menuItem in items)
        [path appendFormat:@"%@%@", menuItem.title, Delimeter];

    if (path.length > Delimeter.length)
        [path deleteCharactersInRange:NSMakeRange(path.length - Delimeter.length, Delimeter.length)];

    return path;
}

@end
