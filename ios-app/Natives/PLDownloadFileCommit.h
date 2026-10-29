#ifndef PL_DOWNLOAD_FILE_COMMIT_H
#define PL_DOWNLOAD_FILE_COMMIT_H
#include <errno.h>
#include <stdio.h>
#include <string.h>
// The caller verifies bytes/hash and stages on the destination's filesystem first.
// rename() preserves an existing destination if the operation fails.
static inline int PLDownloadCommitStagedFile(const char *staged, const char *destination) {
    if (!staged || !destination || !strcmp(staged, destination)) { errno = EINVAL; return -1; }
    return rename(staged, destination);
}
#endif
