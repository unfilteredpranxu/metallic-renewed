"""macOS test: compile the actual production publication/checksum methods with Foundation.
No network, app data or production source edits. All files live under a temporary directory.
"""
import pathlib,subprocess,tempfile
source=pathlib.Path('ios-app/Natives/MinecraftResourceDownloadTask.m').read_text()
def method(prefix):
 a=source.index(prefix);b=source.index('{',a);depth=1;i=b+1
 while depth:
  depth+=(source[i]=='{')-(source[i]=='}');i+=1
 return source[a:i]
body=method('- (NSError *)mc_publishStagedFile:')+'\n'+method('- (BOOL)checkSHAIgnorePref:')
preamble='''#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "PLDownloadFileCommit.h"
static BOOL getPrefBool(NSString *key) { return NO; } // Only the debug-log preference in the real checksum method.
@interface DownloadPublicationTest : NSObject
@property(nonatomic,strong) NSProgress *progress;
@end
@implementation DownloadPublicationTest
'''
tests=r'''
@end
int main(void) { @autoreleasepool {
 NSFileManager *fm=NSFileManager.defaultManager;
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]);
 NSString *dest=[root stringByAppendingPathComponent:@"final.jar"], *part=[root stringByAppendingPathComponent:@"staged.part"];
 DownloadPublicationTest *t=[DownloadPublicationTest new];t.progress=[NSProgress progressWithTotalUnitCount:10];
 NSData *old=[@"old-valid" dataUsingEncoding:NSUTF8StringEncoding],*fresh=[@"abc" dataUsingEncoding:NSUTF8StringEncoding];
 assert([old writeToFile:dest atomically:YES]);assert([fresh writeToFile:part atomically:YES]);
 NSString *sha=@"a9993e364706816aba3e25717850c26c9cd0d89d";
 // Bad length and checksum must preserve both the destination and staged bytes until cleanup/retry.
 assert([t mc_publishStagedFile:part toPath:dest size:4 sha:sha altName:nil]);assert([[NSData dataWithContentsOfFile:dest] isEqual:old]);
 assert([t mc_publishStagedFile:part toPath:dest size:3 sha:@"bad" altName:nil]);assert([[NSData dataWithContentsOfFile:dest] isEqual:old]);
 [t.progress cancel];assert([t mc_publishStagedFile:part toPath:dest size:3 sha:sha altName:nil]);assert([[NSData dataWithContentsOfFile:dest] isEqual:old]);
 t.progress=[NSProgress progressWithTotalUnitCount:10];
 assert(![t mc_publishStagedFile:part toPath:dest size:3 sha:sha altName:nil]);assert([[NSData dataWithContentsOfFile:dest] isEqual:fresh]);assert(![fm fileExistsAtPath:part]);
 assert([t mc_publishStagedFile:part toPath:dest size:3 sha:sha altName:nil]);assert([[NSData dataWithContentsOfFile:dest] isEqual:fresh]);
 assert([fresh writeToFile:part atomically:YES]);assert([t mc_publishStagedFile:part toPath:root size:3 sha:sha altName:nil]);assert([[NSData dataWithContentsOfFile:dest] isEqual:fresh]);
 assert([fm removeItemAtPath:root error:nil]);puts("PASS actual staged publication: length/SHA/cancel/retry/missing/placement failure");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='metallic-publication-') as tmp:
 p=pathlib.Path(tmp);(p/'test.m').write_text(preamble+body+tests)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Werror=implicit-function-declaration','-framework','Foundation','-Iios-app/Natives',str(p/'test.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
