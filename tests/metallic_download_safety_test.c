#define _POSIX_C_SOURCE 200809L
#include "../ios-app/Natives/PLDownloadProgressMath.h"
#include "../ios-app/Natives/PLDownloadFileCommit.h"
#include <assert.h>
#include <stdlib.h>
#include <unistd.h>
static void writeFile(const char *p,const char *v) { FILE *f=fopen(p,"wb");assert(f);assert(fwrite(v,1,strlen(v),f)==strlen(v));assert(!fclose(f)); }
static void expectFile(const char *p,const char *v) { char b[64]={0};FILE *f=fopen(p,"rb");assert(f);assert(fread(b,1,sizeof(b)-1,f)==strlen(v));fclose(f);assert(!strcmp(b,v)); }
int main(void) {
    // Actual old58.33% case: three completed stages plus an indeterminate fourth.
    assert(PLDownloadStageContribution(1,-1)==-1);
    assert(PLDownloadOverallProgress(3,6,1,.58,0)==-1);
    assert(fabs(PLDownloadOverallProgress(3.5,6,0,.58,0)-7.0/12.0)<.000001);
    assert(PLDownloadOverallProgress(6,6,0,1,0)==-1); // Finalization not complete.
    assert(PLDownloadOverallProgress(0,6,1,.58,1)==1);
    assert(PLDownloadOverallProgress(0,0,0,NAN,0)==-1);
    assert(PLDownloadOverallProgress(0,0,0,.58,0)==.58);
    assert(PLDownloadStageContribution(4,0)==1);
    assert(PLDownloadStageContribution(3,.9)==0);
    assert(PLDownloadStageContribution(1,NAN)==-1);
    char dir[]="/tmp/metallic-download-test-XXXXXX";assert(mkdtemp(dir));
    char old[256],part[256],missing[256];snprintf(old,sizeof(old),"%s/final",dir);snprintf(part,sizeof(part),"%s/new.part",dir);snprintf(missing,sizeof(missing),"%s/missing",dir);
    writeFile(old,"valid-existing");writeFile(part,"partial");
    // Interrupted/failed transfer: discard only staging, never a previously valid destination.
    assert(!unlink(part));expectFile(old,"valid-existing");
    assert(PLDownloadCommitStagedFile(missing,old)==-1);expectFile(old,"valid-existing");
    writeFile(part,"verified-retry");assert(PLDownloadCommitStagedFile(part,old)==0);expectFile(old,"verified-retry");assert(access(part,F_OK)!=0);
    assert(PLDownloadCommitStagedFile(old,old)==-1);expectFile(old,"verified-retry");
    writeFile(part,"new-data");assert(PLDownloadCommitStagedFile(part,dir)==-1);expectFile(old,"verified-retry");expectFile(part,"new-data");
    unlink(old);unlink(part);rmdir(dir);puts("PASS progress indeterminate/58%/finalization and atomic destination-preservation tests");
}
