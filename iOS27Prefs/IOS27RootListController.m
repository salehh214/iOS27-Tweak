#import "IOS27RootListController.h"
#import <spawn.h>

extern char **environ;

@implementation IOS27RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respringDevice {
    [self.view endEditing:YES];

    pid_t pid;
    const char *sbreloadPath = "/var/jb/usr/bin/sbreload";
    char *const args[] = { "sbreload", NULL };

    int status = posix_spawn(&pid, sbreloadPath, NULL, NULL, args, environ);
    if (status != 0) {
        // Fallback to killall SpringBoard on rootless if sbreload is unavailable
        const char *killallPath = "/var/jb/usr/bin/killall";
        char *const killArgs[] = { "killall", "-9", "SpringBoard", NULL };
        posix_spawn(&pid, killallPath, NULL, NULL, killArgs, environ);
    }
}

@end
