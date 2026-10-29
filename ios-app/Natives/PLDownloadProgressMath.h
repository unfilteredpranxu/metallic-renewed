#ifndef PL_DOWNLOAD_PROGRESS_MATH_H
#define PL_DOWNLOAD_PROGRESS_MATH_H
#include <math.h>
#include <stddef.h>
// Status values mirror PLTaskStageStatus; adapter assertions guard that contract.
static inline double PLDownloadStageContribution(int status, double progress) {
    if (status == 2 || status == 4) return 1.0;
    if (status != 1) return 0.0;
    if (!isfinite(progress) || progress < 0.0) return -1.0;
    return fmin(1.0, progress);
}
static inline double PLDownloadOverallProgress(double sum, size_t stages, int indeterminate, double taskProgress, int completed) {
    if (completed) return 1.0;
    if (indeterminate) return -1.0;
    double value = stages ? sum / (double)stages : taskProgress;
    // Finished bytes/stages do not prove final placement/installation has completed.
    return isfinite(value) && value >= 0.0 && value < 1.0 ? value : -1.0;
}
#endif
